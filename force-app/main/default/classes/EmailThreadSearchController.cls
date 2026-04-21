public with sharing class EmailThreadSearchController {

    @AuraEnabled(cacheable=false)
    public static List<EmailInboxService.ThreadWrapper> searchThreads(
        String searchTerm, 
        String viewAs, 
        String emailType  // 'inbox', 'archived', 'sent', 'deleted'
    ) {
        List<EmailInboxService.ThreadWrapper> result = new List<EmailInboxService.ThreadWrapper>();

        if (String.isBlank(searchTerm) || String.isBlank(viewAs)) return result;

        // ── 1. Get user email from metadata (same as your pattern) ──
        List<Email_Metadata__mdt> emailMetadatalist = [
            SELECT Id, UserId__c, Email__c 
            FROM Email_Metadata__mdt 
            WHERE UserId__c = :viewAs 
            LIMIT 1
        ];
        String userEmail = emailMetadatalist.isEmpty() ? null : emailMetadatalist[0].Email__c;

        String term = '%' + searchTerm.trim().toLowerCase() + '%';

        // ── 2. Determine email status based on emailType ──
        String emailStatus = (emailType == 'deleted') ? 'Deleted' : 'Active';

        // ── 3. Search threads by Subject ──
        List<Email_Thread__c> threadsBySubject = [
            SELECT Id, Subject__c, Last_Email_Message__c, Last_Email_Track_Time__c
            FROM Email_Thread__c
            WHERE Email_Status__c = :emailStatus
            AND (OwnerId = :viewAs OR Email_Participants__c LIKE :('%' + userEmail + '%'))
            AND Subject__c LIKE :term
            ORDER BY Last_Email_Track_Time__c DESC
            LIMIT 20
        ];

        // ── 4. Search threads by Participant email address ──
        List<Email_Thread__c> threadsByEmail = [
            SELECT Id, Subject__c, Last_Email_Message__c, Last_Email_Track_Time__c
            FROM Email_Thread__c
            WHERE Email_Status__c = :emailStatus
            AND (OwnerId = :viewAs OR Email_Participants__c LIKE :('%' + userEmail + '%'))
            AND Email_Participants__c LIKE :term
            ORDER BY Last_Email_Track_Time__c DESC
            LIMIT 20
        ];

        // ── 5. Merge & deduplicate (same reason as before — OR kills index) ──
        Map<Id, Email_Thread__c> mergedThreadMap = new Map<Id, Email_Thread__c>();
        for (Email_Thread__c t : threadsBySubject) mergedThreadMap.put(t.Id, t);
        for (Email_Thread__c t : threadsByEmail)   mergedThreadMap.put(t.Id, t);

        if (mergedThreadMap.isEmpty()) return result;

        Set<Id> threadIds = mergedThreadMap.keySet();

        // ── 6. Fetch messages — exact same fields as your getThreads() ──
        List<Email_Message__c> rawMessages = [
            SELECT Id, Email_Thread__c, From_Address__c, Body__c, Email_Date__c, 
                   To_Address__c, CC_Address_List__c, Task_Created__c, 
                   Email_Thread__r.CreatedDate, Case_Created__c, Display_To_Address__c, 
                   Thread_Subject__c, To_address_List__c, Rich_Text_Body__c, OwnerId, 
                   Email_Thread__r.Last_Email_Message__c
            FROM Email_Message__c
            WHERE Email_Thread__c IN :threadIds
            ORDER BY Email_Date__c DESC
        ];

        // ── 7. Apply same filters as your getThreads() ──
        List<Email_Message__c> messages = new List<Email_Message__c>();
        for (Email_Message__c msg : rawMessages) {
            Boolean isOwner = msg.OwnerId == viewAs;
            Boolean isInTo  = msg.To_address_List__c != null && msg.To_address_List__c.contains(userEmail);
            Boolean isInCC  = msg.CC_Address_List__c != null && msg.CC_Address_List__c.contains(userEmail);

            // Apply archive filter — same logic as your class
            if (emailType == 'archived') {
                if (!ArchiveRuleService.shouldArchive(msg.From_Address__c, msg.Thread_Subject__c)) continue;
            } else {
                if (ArchiveRuleService.shouldArchive(msg.From_Address__c, msg.Thread_Subject__c)) continue;
            }

            if (isOwner || isInTo || isInCC) {
                messages.add(msg);
            }
        }

        if (messages.isEmpty()) return result;

        // ── 8. Collect message IDs for attachment query ──
        Set<Id> messageIds = new Set<Id>();
        for (Email_Message__c msg : messages) messageIds.add(msg.Id);

        // ── 9. Fetch attachments — exact same as your pattern ──
        Map<Id, List<EmailInboxService.FileData>> fileMap = new Map<Id, List<EmailInboxService.FileData>>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId, LinkedEntityId, ContentDocument.Title, 
                   ContentDocument.LatestPublishedVersionId, ContentDocument.FileExtension
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :messageIds
        ]) {
            EmailInboxService.FileData fd = new EmailInboxService.FileData();
            fd.contentDocumentId = cdl.ContentDocumentId;
            fd.title             = cdl.ContentDocument.Title;
            fd.fileType          = cdl.ContentDocument.FileExtension;
            fd.versionId         = cdl.ContentDocument.LatestPublishedVersionId;

            if (!fileMap.containsKey(cdl.LinkedEntityId)) fileMap.put(cdl.LinkedEntityId, new List<EmailInboxService.FileData>());
            fileMap.get(cdl.LinkedEntityId).add(fd);
        }

        // ── 10. Map messages → threads (exact same as your pattern) ──
        Map<Id, List<EmailInboxService.MessageWrapper>> threadMsgMap = new Map<Id, List<EmailInboxService.MessageWrapper>>();
        for (Email_Message__c msg : messages) {
            EmailInboxService.MessageWrapper mw = new EmailInboxService.MessageWrapper();
            mw.sender        = msg.From_Address__c;
            mw.body          = msg.Rich_Text_Body__c != null ? msg.Rich_Text_Body__c : msg.Body__c;
            mw.emailDate     = msg.Email_Thread__r.Last_Email_Message__c != null 
                                ? msg.Email_Thread__r.Last_Email_Message__c 
                                : msg.Email_Thread__r.CreatedDate;
            mw.toAddress     = msg.To_Address__c != null ? msg.To_Address__c : msg.To_address_List__c;
            mw.messageId     = msg.Id;
            mw.ccAddress     = msg.CC_Address_List__c;
            mw.actualToAddress = msg.Display_To_Address__c;
            mw.attachments   = fileMap.containsKey(msg.Id) ? fileMap.get(msg.Id) : new List<EmailInboxService.FileData>();

            if (!threadMsgMap.containsKey(msg.Email_Thread__c)) threadMsgMap.put(msg.Email_Thread__c, new List<EmailInboxService.MessageWrapper>());
            threadMsgMap.get(msg.Email_Thread__c).add(mw);
        }

        // ── 11. Build final ThreadWrapper response ──
        for (Email_Thread__c th : mergedThreadMap.values()) {
            if (!threadMsgMap.containsKey(th.Id) || threadMsgMap.get(th.Id).isEmpty()) continue;

            EmailInboxService.ThreadWrapper tw = new EmailInboxService.ThreadWrapper();
            tw.threadId = th.Id;
            tw.subject  = th.Subject__c;
            tw.messages = threadMsgMap.get(th.Id);
            result.add(tw);
        }

        return result;
    }
}