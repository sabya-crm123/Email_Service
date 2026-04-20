public with sharing class EmailInboxService {
    
    // Wrapper Classes
    public class ThreadWrapper {
        @AuraEnabled public Id threadId;
        @AuraEnabled public String subject;
        @AuraEnabled public List<MessageWrapper> messages;
    }
    
    public class MessageWrapper {
        @AuraEnabled public String sender;
        @AuraEnabled public String body;
        @AuraEnabled public Datetime emailDate;
        @AuraEnabled public String toAddress;
        @AuraEnabled public String messageId;
        @AuraEnabled public String ccAddress;
        @AuraEnabled public Boolean isCase;
        @AuraEnabled public Boolean isTask;
        @AuraEnabled public Boolean isOpportunity;
        @AuraEnabled public Boolean isOpportunityLinked;
        @AuraEnabled public String actualToAddress;
        
        @AuraEnabled public List<FileData> attachments;
    }
    
    public class FileData {
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileType;
        @AuraEnabled public Id versionId; 
    }
    
    public class FileWrapper {
        @AuraEnabled public String fileName;
        @AuraEnabled public String base64;
        @AuraEnabled public String mimeType;
    }   
    
    @AuraEnabled(cacheable=false)
    public static List<ThreadWrapper> getThreads(Integer offsetSize, Integer batchSize, String viewAs, String emailType) {
        List<ThreadWrapper> result = new List<ThreadWrapper>();
    
        List<Email_Metadata__mdt> emailMetadatalist = [
            SELECT Id, UserId__c, Email__c FROM Email_Metadata__mdt 
            WHERE UserId__c =: viewAs LIMIT 1
        ];
        String userEmail = emailMetadatalist.isEmpty() ? null : emailMetadatalist[0].Email__c;
    
        // Step 1: Fetch a LARGER batch of threads to filter from
        // We over-fetch because archive filtering will reduce the count
        Integer fetchMultiplier = 5; // tune this based on your archive ratio
        List<Email_Thread__c> candidateThreads = [
            SELECT Id, Subject__c, Last_Email_Message__c 
            FROM Email_Thread__c 
            WHERE Email_Status__c = 'Active' 
            AND (OwnerId =: viewAs OR Email_Participants__c LIKE :('%' + userEmail + '%'))
            ORDER BY Last_Email_Track_Time__c DESC 
            LIMIT :(batchSize * fetchMultiplier) OFFSET :offsetSize
        ];
    
        if (candidateThreads.isEmpty()) return result;
    
        Set<Id> candidateThreadIds = new Set<Id>();
        for (Email_Thread__c th : candidateThreads) candidateThreadIds.add(th.Id);
    
        // Step 2: Fetch all messages for these candidate threads
        List<Email_Message__c> rawMessages = [
            SELECT Id, Email_Thread__c, From_Address__c, Body__c, Email_Date__c, 
                   To_Address__c, CC_Address_List__c, Task_Created__c, 
                   Email_Thread__r.CreatedDate, Case_Created__c, Display_To_Address__c, 
                   Thread_Subject__c, To_address_List__c, Rich_Text_Body__c, OwnerId, 
                   Email_Thread__r.Last_Email_Message__c 
            FROM Email_Message__c 
            WHERE Email_Thread__c IN :candidateThreadIds
            ORDER BY Email_Date__c DESC
        ];
    
        // Step 3: Filter messages AND track which thread IDs survive
        Set<Id> survivingThreadIds = new Set<Id>();
        List<Email_Message__c> messages = new List<Email_Message__c>();
    
        for (Email_Message__c msg : rawMessages) {
            Boolean isOwner = msg.OwnerId == viewAs;
            Boolean isInTo  = msg.To_address_List__c != null && msg.To_address_List__c.contains(userEmail);
            Boolean isInCC  = msg.CC_Address_List__c != null && msg.CC_Address_List__c.contains(userEmail);
    
            if (!(isOwner || isInTo || isInCC)) continue;
    
            Boolean shouldArchiveMsg = ArchiveRuleService.shouldArchive(msg.From_Address__c, msg.Thread_Subject__c);
    
            if (emailType == 'archived' && !shouldArchiveMsg) continue;
            if (emailType != 'archived' && shouldArchiveMsg) continue;
    
            messages.add(msg);
            survivingThreadIds.add(msg.Email_Thread__c);
        }
    
        // Step 4: Trim to batchSize surviving threads (maintain original order)
        List<Email_Thread__c> threads = new List<Email_Thread__c>();
        Set<Id> addedThreadIds = new Set<Id>();
        for (Email_Thread__c th : candidateThreads) {
            if (survivingThreadIds.contains(th.Id) && !addedThreadIds.contains(th.Id)) {
                threads.add(th);
                addedThreadIds.add(th.Id);
                if (threads.size() == batchSize) break; // stop once we have enough
            }
        }
    
        // Step 5: Attachments
        Set<Id> messageIds = new Set<Id>();
        for (Email_Message__c msg : messages) {
            if (addedThreadIds.contains(msg.Email_Thread__c)) messageIds.add(msg.Id);
        }
    
        Map<Id, List<FileData>> fileMap = new Map<Id, List<FileData>>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId, LinkedEntityId, ContentDocument.Title, 
                   ContentDocument.LatestPublishedVersionId, ContentDocument.FileExtension 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId IN :messageIds
        ]) {
            FileData fd = new FileData();
            fd.contentDocumentId = cdl.ContentDocumentId;
            fd.title = cdl.ContentDocument.Title;
            fd.fileType = cdl.ContentDocument.FileExtension;
            fd.versionId = cdl.ContentDocument.LatestPublishedVersionId;
            if (!fileMap.containsKey(cdl.LinkedEntityId)) fileMap.put(cdl.LinkedEntityId, new List<FileData>());
            fileMap.get(cdl.LinkedEntityId).add(fd);
        }
    
        // Step 6: Map messages to threads
        Map<Id, List<MessageWrapper>> threadMap = new Map<Id, List<MessageWrapper>>();
        for (Email_Message__c msg : messages) {
            if (!addedThreadIds.contains(msg.Email_Thread__c)) continue;
    
            MessageWrapper mw = new MessageWrapper();
            mw.sender = msg.From_Address__c;
            mw.body = msg.Rich_Text_Body__c != null ? msg.Rich_Text_Body__c : msg.Body__c;
            mw.emailDate = msg.Email_Thread__r.Last_Email_Message__c != null 
                ? msg.Email_Thread__r.Last_Email_Message__c 
                : msg.Email_Thread__r.CreatedDate;
            mw.toAddress = msg.To_Address__c != null ? msg.To_Address__c : msg.To_address_List__c;
            mw.messageId = msg.Id;
            mw.ccAddress = msg.CC_Address_List__c;
            mw.actualToAddress = msg.Display_To_Address__c;
            mw.attachments = fileMap.containsKey(msg.Id) ? fileMap.get(msg.Id) : new List<FileData>();
    
            if (!threadMap.containsKey(msg.Email_Thread__c)) threadMap.put(msg.Email_Thread__c, new List<MessageWrapper>());
            threadMap.get(msg.Email_Thread__c).add(mw);
        }
    
        // Step 7: Build result
        for (Email_Thread__c th : threads) {
            if (!threadMap.containsKey(th.Id) || threadMap.get(th.Id).isEmpty()) continue;
            ThreadWrapper tw = new ThreadWrapper();
            tw.threadId = th.Id;
            tw.subject = th.Subject__c;
            tw.messages = threadMap.get(th.Id);
            result.add(tw);
        }
    
        return result;
    }
    
    
    @AuraEnabled(cacheable=false)
    public static List<MessageWrapper> getThreadMessages(Id threadId, Integer offsetSize, Integer batchSize, String viewAs) {
              
        List<Email_Metadata__mdt> emailMetadatalist = [Select Id, UserId__c, Email__c from Email_Metadata__mdt where UserId__c =: viewAs limit 1];        
        String userEmail = (emailMetadatalist.isEmpty()) ? null : emailMetadatalist[0].Email__c;   
        
        // Collect message IDs for attachments
        List<Email_Message__c> rawMessages = [SELECT Id, Email_Thread__c, From_Address__c, Body__c, Email_Date__c, To_Address__c, CC_Address_List__c, Task_Created__c,
                                           Case_Created__c, Display_To_Address__c, Opportunity_Linked__c, Opportunity_Created__c, To_address_List__c, OwnerId, Rich_Text_Body__c FROM Email_Message__c WHERE 
                                              Email_Thread__c = : threadId                                           
                                           ORDER BY Email_Date__c DESC]; 
        if(rawMessages.isEmpty()) return new List<MessageWrapper>();
        
        List<Email_Message__c> messages = new List<Email_Message__c>();
        for (Email_Message__c msg : rawMessages) {
            Boolean isOwner    = msg.OwnerId == viewAs;
            Boolean isInTo     = msg.To_address_List__c != null && msg.To_address_List__c.contains(userEmail);
            Boolean isInCC     = msg.CC_Address_List__c != null && msg.CC_Address_List__c.contains(userEmail);
            
            if (isOwner || isInTo || isInCC) {
                messages.add(msg);
            }
        }
        
        Set<Id> messageIds = new Set<Id>();
        for (Email_Message__c msg : messages) messageIds.add(msg.Id);                
        
        Map<Id, List<FileData>> fileMap = new Map<Id, List<FileData>>();
        for(ContentDocumentLink cdl : [
            SELECT ContentDocumentId, LinkedEntityId,
            ContentDocument.Title, ContentDocument.LatestPublishedVersionId,
            ContentDocument.FileExtension
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :messageIds
        ]) {
            FileData fd = new FileData();
            fd.contentDocumentId = cdl.ContentDocumentId;
            fd.title = cdl.ContentDocument.Title;
            fd.fileType = cdl.ContentDocument.FileExtension;
            fd.versionId = cdl.ContentDocument.LatestPublishedVersionId;
            
            if(!fileMap.containsKey(cdl.LinkedEntityId)) {
                fileMap.put(cdl.LinkedEntityId, new List<FileData>());
            }
            fileMap.get(cdl.LinkedEntityId).add(fd);
        }
        
        // Map messages to wrapper
        List<MessageWrapper> result = new List<MessageWrapper>();
        for(Email_Message__c msg : messages) {
            MessageWrapper mw = new MessageWrapper();
            mw.sender = msg.From_Address__c;
            mw.body = (msg.Rich_Text_Body__c != null ? msg.Rich_Text_Body__c : msg.Body__c) ;
            mw.emailDate = msg.Email_Date__c;  
            
            String combinedToAddress = '';
            List<String> allToAddresses = new List<String>();
            
            if (msg.To_Address__c != null) {
                allToAddresses.add(msg.To_Address__c.trim());
            }
            if (msg.From_Address__c != null) {
                allToAddresses.add(msg.From_Address__c.trim());
            }
            
            if (msg.To_address_List__c != null) {
                for (String addr : msg.To_address_List__c.split(';')) {
                    String trimmed = addr.trim();
                    if (String.isNotBlank(trimmed)) {
                        allToAddresses.add(trimmed);
                    }
                }
            }            
            
            String currentUserEmail = UserInfo.getUserEmail().toLowerCase();
            String customLabelEmail = System.Label.ExcludedEmailAddress.toLowerCase().trim(); // shreyash7u@outlook.com
            
            List<String> filteredAddresses = new List<String>();
            for (String addr : allToAddresses) {
                String lowerAddr = addr.toLowerCase().trim();
                if (lowerAddr != currentUserEmail && lowerAddr != customLabelEmail) {
                    filteredAddresses.add(addr);
                }
            }
            
            combinedToAddress = String.join(filteredAddresses, ',');
            mw.toAddress = combinedToAddress; 
            mw.messageId = msg.Id;
            mw.ccAddress = msg.CC_Address_List__c;
            mw.isCase = msg.Case_Created__c;
            mw.isTask = msg.Task_Created__c;
            mw.isOpportunity = msg.Opportunity_Created__c;
            mw.isOpportunityLinked = msg.Opportunity_Linked__c;
            mw.actualToAddress = msg.Display_To_Address__c;
            mw.attachments = fileMap.containsKey(msg.Id) ? fileMap.get(msg.Id) : new List<FileData>();
            result.add(mw);
        }
        
        return result;
    }
    
    
    @AuraEnabled
    public static void sendEmail(String toAddress, String ccAddress,
        String bccAddress, String subject, String body, List<String> fileNames,
        List<String> fileContents, List<string> contType) {
      	system.debug('Email To #### > ' + parseEmails(toAddress));
      	try {
            if (String.isBlank(toAddress)) {
              throw new AuraHandledException('To address required');
            }
        
            List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
            List<ContentVersion> cversionInsert = new List<ContentVersion>();
        
            for (Integer i = 0; i < fileNames.size(); i++) {
              Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
              attachment.setFileName(fileNames[i]);
              attachment.setBody(EncodingUtil.base64Decode(fileContents[i]));
              attachments.add(attachment);
        
              Blob decodedBlob = EncodingUtil.base64Decode(fileContents[i]);
            }
        
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(parseEmails(toAddress));
        
            if (String.isNotBlank(ccAddress)) {
              mail.setCcAddresses(parseEmails(ccAddress));
            }
            if (String.isNotBlank(bccAddress)) {
              mail.setBccAddresses(parseEmails(bccAddress));
            }
        
            mail.setSubject(subject);
            mail.setHtmlBody(body);
            mail.setFileAttachments(attachments);  
        
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{mail});
        
            Email_Thread__c thread = new Email_Thread__c(Subject__c = subject, Email_Status__c = 'Active');
            insert thread;
        
            // Save Message
            Email_Message__c msg = new Email_Message__c(
                Email_Thread__c = thread.Id,
                From_Address__c = UserInfo.getUserEmail(), 
                To_Address__c = toAddress,
                Body__c = body, 
                Email_Date__c = System.now(), 
                Is_Outgoing__c = true);
            insert msg;
        
            for (Integer i = 0; i < fileNames.size(); i++) {
              Blob decodedBlob = EncodingUtil.base64Decode(fileContents[i]);
              ContentVersion cver = new ContentVersion();
              cver.PathOnClient = fileNames[i] + '.' + contType[i];
              cver.Title = fileNames[i];
              cver.VersionData = decodedBlob;
              cver.FirstPublishLocationId = msg.Id;
              cver.PathOnClient = fileNames[i];
              cversionInsert.add(cver);
            }
            insert cversionInsert;
        
            New_Email__e inbound_event = new New_Email__e();
            inbound_event.MessageId__c = msg.Id;
            Database.SaveResult publish_result = EventBus.publish(inbound_event);
        
            if (publish_result.isSuccess())
              system.debug('success');
            else
              system.debug('fail');
        
          } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
          }
    }
    
    @AuraEnabled(cacheable=false)
    public static List<ThreadWrapper> getSentThreads(String emailStatus, String viewAs) {
        emailStatus = 'Active';
        List<Email_Metadata__mdt> emailMetadatalist = [Select Id, UserId__c, Email__c from Email_Metadata__mdt where UserId__c =: viewAs limit 1];        
        String userEmail = (emailMetadatalist.isEmpty()) ? null : emailMetadatalist[0].Email__c;
        
        system.debug('Email Status >> ' + emailStatus);
        
        String currentUserEmail = UserInfo.getUserEmail();
        
        List<ThreadWrapper> result = new List<ThreadWrapper>();
        List<Email_Thread__c> threads;
        List<Email_Message__c> rawMessages;
        
        
        threads = [SELECT Id, Subject__c, Email_Status__c  FROM Email_Thread__c WHERE Email_Status__c =: emailStatus AND (OwnerId =: viewAs OR 
                                                                Email_Participants__c LIKE :('%' + userEmail + '%')) AND 
                                         Id IN (SELECT Email_Thread__c FROM Email_Message__c
                WHERE From_Address__c = :currentUserEmail) ORDER BY Last_Email_Track_Time__c  DESC];     
            
            rawMessages = [SELECT Id, Email_Thread__r.Last_Email_Message__c, Email_Thread__c, OwnerId, Opportunity_Created__c, Opportunity_Linked__c, To_address_List__c, From_Address__c, Body__c, Email_Date__c, Rich_Text_Body__c, To_Address__c, CC_Address_List__c, Display_To_Address__c
            FROM Email_Message__c WHERE From_Address__c = :currentUserEmail ORDER BY Email_Date__c DESC];    
            
            List<Email_Message__c> messages = new List<Email_Message__c>();
            for (Email_Message__c msg : rawMessages) {
                Boolean isOwner    = msg.OwnerId == viewAs;
                Boolean isInTo     = msg.To_address_List__c != null && msg.To_address_List__c.contains(userEmail);
                Boolean isInCC     = msg.CC_Address_List__c != null && msg.CC_Address_List__c.contains(userEmail);
                
                if (isOwner || isInTo || isInCC) {
                    messages.add(msg);
                }
            }
        
        system.debug(threads.size());   
        
        Set<Id> messageIds = new Set<Id>();
        for (Email_Message__c msg : messages) {
            messageIds.add(msg.Id);
        }
        
        
        Map<Id, List<FileData>> fileMap = new Map<Id, List<FileData>>();
        
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId, LinkedEntityId,
            ContentDocument.Title, ContentDocument.LatestPublishedVersionId,
            ContentDocument.FileExtension
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :messageIds
        ]) {
            FileData fd = new FileData();
            fd.contentDocumentId = cdl.ContentDocumentId;
            fd.title = cdl.ContentDocument.Title;
            fd.fileType = cdl.ContentDocument.FileExtension;
            fd.versionId = cdl.ContentDocument.LatestPublishedVersionId;
            
            if (!fileMap.containsKey(cdl.LinkedEntityId)) {
                fileMap.put(cdl.LinkedEntityId, new List<FileData>());
            }
            
            fileMap.get(cdl.LinkedEntityId).add(fd);
        }
        
        // 5️⃣ Map Messages → Threads
        Map<Id, List<MessageWrapper>> threadMap = new Map<Id, List<MessageWrapper>>();
        
        for (Email_Message__c msg : messages) {
            
            MessageWrapper mw = new MessageWrapper();
            mw.sender = msg.From_Address__c;
            mw.body = (msg.Rich_Text_Body__c != null ? msg.Rich_Text_Body__c : msg.Body__c) ;
            mw.emailDate = (msg.Email_Thread__r.Last_Email_Message__c != null ? msg.Email_Thread__r.Last_Email_Message__c : msg.Email_Thread__r.CreatedDate);
            mw.toAddress = (msg.To_address_List__c != null ? msg.To_address_List__c : msg.To_Address__c);
            mw.messageId = msg.Id;
            mw.ccAddress = msg.CC_Address_List__c;
            
            mw.attachments = fileMap.containsKey(msg.Id)
                ? fileMap.get(msg.Id)
                : new List<FileData>();
            
            if (!threadMap.containsKey(msg.Email_Thread__c)) {
                threadMap.put(msg.Email_Thread__c, new List<MessageWrapper>());
            }
            
            threadMap.get(msg.Email_Thread__c).add(mw);
        }
        
        // 6️⃣ Build Response
        for (Email_Thread__c th : threads) {
            
            ThreadWrapper tw = new ThreadWrapper();
            tw.threadId = th.Id;
            tw.subject = th.Subject__c;
            tw.messages = threadMap.containsKey(th.Id)
                ? threadMap.get(th.Id)
                : new List<MessageWrapper>();
            
            result.add(tw);
        }
        
        return result;
    }
    
    
    @AuraEnabled(cacheable=false)
     public static List<ThreadWrapper> getSendTrashThreads(Integer offsetSize, Integer batchSize, String viewAs, 
                                                           String emailStatus, String emailType) {
        system.debug('Email Status >> ' + emailStatus);
        system.debug('Email Type >> ' + emailType);                                                      
        List<ThreadWrapper> result = new List<ThreadWrapper>();
        
        List<Email_Metadata__mdt> emailMetadatalist = [Select Id, UserId__c, Email__c from Email_Metadata__mdt where UserId__c =: viewAs limit 1];
        
        String userEmail = (emailMetadatalist.isEmpty()) ? null : emailMetadatalist[0].Email__c;
                                                               
        List<Email_Thread__c> threads;            
        Set<Id> threadIds = new Set<Id>();
        List<Email_Message__c> rawMessages;  
         
        if(emailStatus == 'Deleted'){
            
            threads = [SELECT Id, Subject__c, Last_Email_Message__c FROM Email_Thread__c where Email_Status__c = 'Deleted' AND 
                                         (OwnerId =: viewAs OR Email_Participants__c LIKE :('%' + userEmail + '%')) 
                                         ORDER BY Last_Email_Track_Time__c  DESC LIMIT :batchSize OFFSET :offsetSize];
        
            if(threads.isEmpty()) return result;    
            
            for(Email_Thread__c th : threads) threadIds.add(th.Id);
            
            rawMessages = [SELECT Id, Email_Thread__c, From_Address__c, Body__c, Email_Date__c, To_Address__c, CC_Address_List__c, Task_Created__c, Email_Thread__r.CreatedDate,
                                           Case_Created__c, Display_To_Address__c, Thread_Subject__c, To_address_List__c, Rich_Text_Body__c, OwnerId, Email_Thread__r.Last_Email_Message__c FROM Email_Message__c WHERE 
                                              Email_Thread__c IN :threadIds                                           
                                           ORDER BY Email_Date__c DESC];  
            
        }
        else if(emailStatus == 'Active') {
            threads = [SELECT Id, Subject__c, Last_Email_Message__c FROM Email_Thread__c where Email_Status__c = 'Active' AND 
                                         (OwnerId =: viewAs OR Email_Participants__c LIKE :('%' + userEmail + '%')) 
                                         ORDER BY Last_Email_Track_Time__c  DESC LIMIT :batchSize OFFSET :offsetSize];
        
            if(threads.isEmpty()) return result;    
            
            for(Email_Thread__c th : threads) threadIds.add(th.Id);
            
            rawMessages = [SELECT Id, Email_Thread__c, From_Address__c, Body__c, Email_Date__c, To_Address__c, CC_Address_List__c, Task_Created__c, Email_Thread__r.CreatedDate,
                                           Case_Created__c, Display_To_Address__c, Thread_Subject__c, To_address_List__c, Rich_Text_Body__c, OwnerId, Email_Thread__r.Last_Email_Message__c FROM Email_Message__c WHERE 
                                              Email_Thread__c IN :threadIds  AND From_Address__c =: userEmail                                     
                                           ORDER BY Email_Date__c DESC];  
        }
         
         
        List<Email_Message__c> messages = new List<Email_Message__c>();
        for (Email_Message__c msg : rawMessages) {
            Boolean isOwner    = msg.OwnerId == viewAs;
            Boolean isInTo     = msg.To_address_List__c != null && msg.To_address_List__c.contains(userEmail);
            Boolean isInCC     = msg.CC_Address_List__c != null && msg.CC_Address_List__c.contains(userEmail);
            
            if(emailType == 'archived'){
                if (!ArchiveRuleService.shouldArchive(msg.From_Address__c, msg.Thread_Subject__c)) {
                    continue; 
                }
            }
            else{
                if (ArchiveRuleService.shouldArchive(msg.From_Address__c, msg.Thread_Subject__c)) {
                    continue; 
                }
            }
            
            if (isOwner || isInTo || isInCC) {
                messages.add(msg);
            }
        }
        
        Set<Id> messageIds = new Set<Id>();
        for (Email_Message__c msg : messages) messageIds.add(msg.Id);        
        
        Map<Id, List<FileData>> fileMap = new Map<Id, List<FileData>>();
        if (!messageIds.isEmpty()) {                                                   
            for (ContentDocumentLink cdl : [SELECT ContentDocumentId, LinkedEntityId, ContentDocument.Title, ContentDocument.LatestPublishedVersionId,
                ContentDocument.FileExtension FROM ContentDocumentLink WHERE LinkedEntityId IN :messageIds]) {
                FileData fd = new FileData();
                fd.contentDocumentId = cdl.ContentDocumentId;
                fd.title = cdl.ContentDocument.Title;
                fd.fileType = cdl.ContentDocument.FileExtension;
                fd.versionId = cdl.ContentDocument.LatestPublishedVersionId;
                
                if (!fileMap.containsKey(cdl.LinkedEntityId)) fileMap.put(cdl.LinkedEntityId, new List<FileData>());
                fileMap.get(cdl.LinkedEntityId).add(fd);
            }
        }
        
        // 5️⃣ Map Messages to Threads
        Map<Id, List<MessageWrapper>> threadMap = new Map<Id, List<MessageWrapper>>();
        for (Email_Message__c msg : messages) {
            MessageWrapper mw = new MessageWrapper();
            mw.sender = msg.From_Address__c;
            mw.body = (msg.Rich_Text_Body__c != null ? msg.Rich_Text_Body__c : msg.Body__c) ;
            mw.emailDate = (msg.Email_Thread__r.Last_Email_Message__c != null ? msg.Email_Thread__r.Last_Email_Message__c : msg.Email_Thread__r.CreatedDate);
            mw.toAddress = (msg.To_Address__c != null ? msg.To_Address__c : msg.To_address_List__c);
            mw.messageId = msg.Id;
            mw.ccAddress = msg.CC_Address_List__c;
            mw.actualToAddress = msg.Display_To_Address__c;
            mw.attachments = fileMap.containsKey(msg.Id) ? fileMap.get(msg.Id) : new List<FileData>();
            
            if (!threadMap.containsKey(msg.Email_Thread__c)) threadMap.put(msg.Email_Thread__c, new List<MessageWrapper>());
            threadMap.get(msg.Email_Thread__c).add(mw);
        }
        
        // 6️⃣ Build ThreadWrapper response
        for (Email_Thread__c th : threads) {
            if (!threadMap.containsKey(th.Id) || threadMap.get(th.Id).isEmpty()) {
                continue;
            }            
            ThreadWrapper tw = new ThreadWrapper();
            tw.threadId = th.Id;
            tw.subject = th.Subject__c;
            tw.messages =  threadMap.get(th.Id);
            result.add(tw);
        }
        
        return result;
    }
    
    
    private static List<String> parseEmails(String emails) {
        List<String> result = new List<String>();
        
        if(String.isNotBlank(emails)) {
            for(String e : emails.split(',')) {
                if(String.isNotBlank(e)) {
                    result.add(e.trim());
                }
            }
        }
        
        return result;
    }
    
    
    @AuraEnabled
    public static string deleteMessage(String threadId, String actionType){
        try {
           /* List<Email_Message__c> parentMsg = [SELECT Id, Email_Thread__c, Message_Id__c , CC_Address__c, Is_Outgoing__c FROM Email_Message__c 
                                          WHERE Email_Thread__c = :threadId];
            
            if(!parentMsg.isEmpty()){
                delete parentMsg;
            }*/
            
            List<Email_Thread__c> threads = [SELECT Id, Subject__c, Email_Status__c  FROM Email_Thread__c WHERE Id =: threadId];       
            
            if(!threads.isEmpty()){
                for(Email_Thread__c et : threads){
                    if(actionType == 'delete'){
                        et.Email_Status__c = 'Deleted';	
                    }
                    else{
                        et.Email_Status__c = 'Active';	
                    }
                }
                update threads;
            }
            
            return 'success';
        } catch (Exception e) {
            throw new AuraHandledException('Error while saving Task: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void sendReplyEmail(String toAddress, String ccAddress, String subject, String body, String parentMessageId,
                                      List<String> fileNames, List<String> fileContents, List<string> contType){
                                          
        system.debug('Email Body in reply >>> ' + body);
                                          
        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
        List<ContentVersion> cversionInsert = new List<ContentVersion>();
        for (Integer i = 0; i < fileNames.size(); i++) {
             Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
             attachment.setFileName(fileNames[i]);
             attachment.setBody(EncodingUtil.base64Decode(fileContents[i]));
             attachments.add(attachment);            
                                             
             Blob decodedBlob = EncodingUtil.base64Decode(fileContents[i]);
         }
                                          
        system.debug('Email Message >> ' + parentMessageId);
        
        Email_Message__c parentMsg = [SELECT Id, Email_Thread__c, Message_Id__c , CC_Address__c, Is_Outgoing__c FROM Email_Message__c 
                                      WHERE Id = :parentMessageId LIMIT 1];
        
        
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        
        mail.setToAddresses(parseEmails(toAddress));
        
        if(String.isNotBlank(ccAddress)){
            List<String> ccAdd = ccAddress.split(',');
            if(parentMsg.CC_Address__c != null){
                ccAdd.add(parentMsg.CC_Address__c);
            }
            mail.setCcAddresses(ccAdd);
        }
        
       
        mail.setHtmlBody(body);   
        String messageId = generateMessageId();
		
        
        if(!Test.isRunningTest() && parentMsg.Is_Outgoing__c == false){
            mail.setInReplyTo(parentMsg.Message_Id__c);
        	mail.setReferences(parentMsg.Message_Id__c);
            
        }
        
        String finalSubject = subject;

        if(parentMsg.Is_Outgoing__c == true && String.isNotBlank(subject)){
            if(subject.toLowerCase().startsWith('Re: ')){
                finalSubject = subject.substring(3).trim();
            }
        }
        
        mail.setSubject(finalSubject);
        
        mail.setSubject(subject);    
        mail.setFileAttachments(attachments); 
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{mail});
        
        Email_Message__c newMsg = new Email_Message__c(
            Email_Thread__c = parentMsg.Email_Thread__c,
            From_Address__c = UserInfo.getUserEmail(),
            To_address_List__c = toAddress,
            CC_Address__c = ccAddress,
            Rich_Text_Body__c = body,
            Email_Date__c = System.now(),
            Message_Id__c = messageId, 
            //Reply_To_Message_ID__c = parentMsg.Message_Id__c,
            Is_Outgoing__c = true
        );
        
        insert newMsg;
        
        New_Email__e inbound_event = new New_Email__e ();
        inbound_event.MessageId__c = newMsg.Id;
        Database.SaveResult publish_result = EventBus.publish(inbound_event);
        
        if(publish_result.isSuccess()) system.debug('success');
        else system.debug('fail');
                                          
        for (Integer i = 0; i < fileNames.size(); i++) {                
            Blob decodedBlob = EncodingUtil.base64Decode(fileContents[i]);
            ContentVersion cver = new ContentVersion();
            cver.PathOnClient = fileNames[i]+'.'+contType[i];
            cver.Title  = fileNames[i];
            cver.VersionData = decodedBlob;
            cver.FirstPublishLocationId = newMsg.Id;
            cver.PathOnClient = fileNames[i];
            cversionInsert.add(cver);
         }
         insert cversionInsert;
                
    }
    
    private static String generateMessageId(){
        return '<' + String.valueOf(Crypto.getRandomLong()) + '@cloudexperts.com>';
    }
}


/* @AuraEnabled(cacheable=false)
public static List<ThreadWrapper> getThreads() {

List<ThreadWrapper> result = new List<ThreadWrapper>();

// 1️⃣ Get Threads
List<Email_Thread__c> threads = [
SELECT Id, Subject__c
FROM Email_Thread__c
ORDER BY CreatedDate DESC
];

// 2️⃣ Get Messages
List<Email_Message__c> messages = [
SELECT Id, Email_Thread__c, From_Address__c, Body__c, Email_Date__c, 
To_Address__c, CC_Address_List__c
FROM Email_Message__c
ORDER BY Email_Date__c ASC
];

// 3️⃣ Collect Message IDs
Set<Id> messageIds = new Set<Id>();
for (Email_Message__c msg : messages) {
messageIds.add(msg.Id);
}

// 4️⃣ Fetch Attachments (ContentDocumentLink)
Map<Id, List<FileData>> fileMap = new Map<Id, List<FileData>>();

for (ContentDocumentLink cdl : [
SELECT ContentDocumentId, LinkedEntityId,
ContentDocument.Title, ContentDocument.LatestPublishedVersionId,
ContentDocument.FileExtension
FROM ContentDocumentLink
WHERE LinkedEntityId IN :messageIds
]) {
FileData fd = new FileData();
fd.contentDocumentId = cdl.ContentDocumentId;
fd.title = cdl.ContentDocument.Title;
fd.fileType = cdl.ContentDocument.FileExtension;
fd.versionId = cdl.ContentDocument.LatestPublishedVersionId;

if (!fileMap.containsKey(cdl.LinkedEntityId)) {
fileMap.put(cdl.LinkedEntityId, new List<FileData>());
}

fileMap.get(cdl.LinkedEntityId).add(fd);
}

// 5️⃣ Map Messages to Threads
Map<Id, List<MessageWrapper>> threadMap = new Map<Id, List<MessageWrapper>>();

for (Email_Message__c msg : messages) {

MessageWrapper mw = new MessageWrapper();
mw.sender = msg.From_Address__c;
mw.body = msg.Body__c;
mw.emailDate = msg.Email_Date__c;
mw.toAddress = msg.To_Address__c;
mw.messageId = msg.Id;
mw.ccAddress = msg.CC_Address_List__c;

// ✅ Attach files to message
mw.attachments = fileMap.containsKey(msg.Id)
? fileMap.get(msg.Id)
: new List<FileData>();

if (!threadMap.containsKey(msg.Email_Thread__c)) {
threadMap.put(msg.Email_Thread__c, new List<MessageWrapper>());
}

threadMap.get(msg.Email_Thread__c).add(mw);
}

// 6️⃣ Build Final Response
for (Email_Thread__c th : threads) {

ThreadWrapper tw = new ThreadWrapper();
tw.threadId = th.Id;
tw.subject = th.Subject__c;
tw.messages = threadMap.containsKey(th.Id)
? threadMap.get(th.Id)
: new List<MessageWrapper>();

result.add(tw);
}

return result;
}*/