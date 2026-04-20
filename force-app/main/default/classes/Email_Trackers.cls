global inherited sharing class Email_Trackers implements Messaging.InboundEmailHandler {

    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {

        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();

        try {

            String subject = normalizeSubject(email.subject);
            String body = email.plainTextBody;
            String htmlBody = email.htmlBody;

            if (String.isBlank(body)) {
                body = htmlBody != null ? htmlBody : '';
            }

            System.debug('Email Subject >> ' + email.Subject);
            System.debug('Email body >> ' + email.plainTextBody);

            // ✅ FIX 1: Null-safe debug for toAddresses
            if (email.toAddresses != null) {
                System.debug('Email To >> ' + String.join(email.toAddresses, ';'));
            }

            String senderEmail = email.fromAddress;

            // ✅ FIX 2: Null-safe toAddress parsing
            String toAddress = null;
            
            String additionalToAddresses = null;

            if (email.toAddresses != null && !email.toAddresses.isEmpty()) {
                toAddress = email.toAddresses[0];
                if (email.toAddresses.size() > 1) {
                    List<String> remaining = new List<String>();
                    for (Integer i = 1; i < email.toAddresses.size(); i++) {
                        remaining.add(email.toAddresses[i]);
                    }
                    additionalToAddresses = String.join(remaining, ',');
                }
            } else {
                toAddress = envelope.toAddress;
            }

            String ccAddress = (email.ccAddresses != null) ? String.join(email.ccAddresses, ',') : null;
            System.debug('CC Address >> ' + email.ccAddresses);

            // ✅ FIX 3: Only extract forwarded sender when subject is actually a forward
            if (String.isNotBlank(subject) &&
               (subject.toLowerCase().startsWith('fwd') || subject.toLowerCase().startsWith('fw'))) {

                Pattern emailPattern = Pattern.compile('(?i)From:\\s*.*?<([\\w.%+-]+@[\\w.-]+\\.[a-zA-Z]{2,})>');
                Matcher emailMatcher = emailPattern.matcher(body);
                if (emailMatcher.find()) {
                    senderEmail = emailMatcher.group(1);
                }
            }

            // 🧠 Extract EMAIL HEADERS
            String messageId = null;
            String inReplyTo = null;

            if (email.headers != null) {
                for (Messaging.InboundEmail.Header h : email.headers) {
                    if (h.name != null) {
                        if (h.name.equalsIgnoreCase('Message-ID')) {
                            messageId = cleanHeader(h.value);
                        }
                        if (h.name.equalsIgnoreCase('In-Reply-To')) {
                            inReplyTo = cleanHeader(h.value);
                        }
                    }
                }
            }

            System.debug('MessageId: ' + messageId);
            System.debug('InReplyTo: ' + inReplyTo);

            // ❌ DUPLICATE CHECK
            if (messageId != null) {
                List<Email_Message__c> existing = [
                    SELECT Id FROM Email_Message__c
                    WHERE Message_Id__c = :messageId
                    LIMIT 1
                ];
                if (!existing.isEmpty()) {
                    System.debug('Duplicate email skipped: ' + messageId);
                    result.success = true;
                    return result;
                }
            }

            // 🔗 FIND THREAD
            Id threadId = findThread(messageId, inReplyTo, subject);
            
            List<String> allParticipants = new List<String>();
            
            if (email.toAddresses != null && !email.toAddresses.isEmpty()) {
                allParticipants.addAll(email.toAddresses);
            } else if (toAddress != null) {
                allParticipants.add(toAddress);
            }
            
            Set<String> uniqueParticipants2 = new Set<String>(allParticipants);  
            
            if (email.ccAddresses != null && !email.ccAddresses.isEmpty()) {
                allParticipants.addAll(email.ccAddresses);
            }         
            
            if (String.isNotBlank(senderEmail)) {
                allParticipants.add(senderEmail);
            }         
            
            String participantList = String.join(new List<String>(uniqueParticipants2), ',');
            
            if (threadId == null) {
                Set<String> uniqueParticipants = new Set<String>(allParticipants);            
                Email_Thread__c thread = new Email_Thread__c(
                    Subject__c = subject != null && subject.length() > 255 ? subject.substring(0, 255) : subject,
                    Email_Status__c = 'Active',
                    Email_Participants__c = String.join(new List<String>(uniqueParticipants), ',')
                );
                insert thread;
                threadId = thread.Id;
            } else {
                Email_Thread__c existingThread = [
                    SELECT Id, Email_Participants__c
                    FROM Email_Thread__c
                    WHERE Id = :threadId
                    LIMIT 1
                ];

                Set<String> mergedParticipants = new Set<String>();

                if (existingThread.Email_Participants__c != null) {
                    for (String p : existingThread.Email_Participants__c.split(',')) {
                        String trimmed = p.trim();
                        if (String.isNotBlank(trimmed)) mergedParticipants.add(trimmed.toLowerCase());
                    }
                }
            
                // Merge in new participants (lowercased for dedup)
                for (String p : allParticipants) {
                    if (String.isNotBlank(p)) mergedParticipants.add(p.trim().toLowerCase());
                }
            
                existingThread.Email_Participants__c = String.join(new List<String>(mergedParticipants), ',');
                update existingThread;
            }

            // 💾 SAVE MESSAGE
            // ✅ FIX 6: Null-safe To_address_List__c
           
            Integer MAX_LENGTH = 131072;

            String plainBody = body;
            String richBody = htmlBody;
            
            if (plainBody != null && plainBody.length() > MAX_LENGTH) {
                plainBody = plainBody.substring(0, MAX_LENGTH);
            }
            
            if (richBody != null && richBody.length() > MAX_LENGTH) {
                richBody = richBody.substring(0, MAX_LENGTH);
            }
            
            Email_Message__c msg = new Email_Message__c(
                Email_Thread__c = threadId,
                From_Address__c = senderEmail,
                To_address_List__c = participantList,
                CC_Address_List__c = ccAddress,
                Body__c = plainBody,
                Rich_Text_Body__c = richBody,
                Email_Date__c = System.now(),
                Message_Id__c = messageId,
                Reply_To_Message_ID__c = inReplyTo
            );

            insert msg;

            // 📡 PUBLISH EVENT
            New_Email__e inbound_event = new New_Email__e();
            inbound_event.MessageId__c = msg.Id;
            Database.SaveResult publish_result = EventBus.publish(inbound_event);

            if (publish_result.isSuccess()) {
                System.debug('Platform event published successfully');
            } else {
                System.debug('Platform event publish failed: ' + publish_result.getErrors());
            }

            // 📎 SAVE ATTACHMENTS
            saveAttachments(email, msg.Id);

            System.debug('Email saved successfully. Record: ' + msg.Id + ' | Thread: ' + threadId);

        } catch (Exception e) {
            // ✅ FIX 7: Expose the error properly so email is NOT silently lost
            System.debug('ERROR in Email_Trackers: ' + e.getMessage() + ' | Line: ' + e.getLineNumber() + ' | Stack: ' + e.getStackTraceString());
            result.success = false;
            result.message = 'Email processing failed: ' + e.getMessage();
        }

        return result;
    }

    // 🔗 THREAD FINDING
    private Id findThread(String messageId, String inReplyTo, String subject) {

        Set<String> referencedIds = new Set<String>();

        if (inReplyTo != null) {
            List<String> replyIds = inReplyTo.split('[,\\s]+');
            for (String rid : replyIds) {
                rid = rid.trim();
                if (String.isNotBlank(rid)) referencedIds.add(rid);
            }
        }

        if (!referencedIds.isEmpty()) {
            List<Email_Message__c> parentMsgs = [
                SELECT Id, Email_Thread__c
                FROM Email_Message__c
                WHERE Message_Id__c IN :referencedIds
                AND Email_Thread__c != null
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            if (!parentMsgs.isEmpty()) {
                return parentMsgs[0].Email_Thread__c;
            }
        }

        if (messageId != null) {
            List<Email_Message__c> existing = [
                SELECT Id, Email_Thread__c
                FROM Email_Message__c
                WHERE Message_Id__c = :messageId
                AND Email_Thread__c != null
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return existing[0].Email_Thread__c;
            }
        }

        // ✅ FIX 8: Subject fallback scoped to last 30 days to avoid cross-merging old threads
        if (String.isNotBlank(subject)) {
            Datetime cutoff = System.now().addDays(-30);

            List<Email_Thread__c> threads = [
                SELECT Id
                FROM Email_Thread__c
                WHERE Subject__c = :subject
                AND Email_Status__c = 'Active'
                AND CreatedDate >= :cutoff
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!threads.isEmpty()) {
                return threads[0].Id;
            }
        }

        return null;
    }

    // 🧹 CLEAN HEADER
    private String cleanHeader(String value) {
        if (String.isBlank(value)) return value;
        return value.replace('<', '').replace('>', '').trim();
    }

    // 🧹 SUBJECT NORMALIZATION
    private String normalizeSubject(String subject) {
        if (String.isBlank(subject)) return 'No Subject';
        String cleanSubject = subject;
        while (cleanSubject.toLowerCase().startsWith('re:') ||
               cleanSubject.toLowerCase().startsWith('fwd:') ||
               cleanSubject.toLowerCase().startsWith('fw:')) {
            cleanSubject = cleanSubject.substringAfter(':').trim();
        }
        return cleanSubject;
    }

    // 📎 SAVE ATTACHMENTS
    private void saveAttachments(Messaging.InboundEmail email, Id msgId) {

        List<ContentVersion> cvList = new List<ContentVersion>();

        if (email.binaryAttachments != null) {
            for (Messaging.InboundEmail.BinaryAttachment b : email.binaryAttachments) {
                cvList.add(new ContentVersion(
                    Title = b.fileName,
                    PathOnClient = b.fileName,
                    VersionData = b.body,
                    FirstPublishLocationId = msgId
                ));
            }
        }

        if (email.textAttachments != null) {
            for (Messaging.InboundEmail.TextAttachment t : email.textAttachments) {
                cvList.add(new ContentVersion(
                    Title = t.fileName,
                    PathOnClient = t.fileName,
                    VersionData = Blob.valueOf(t.body),
                    FirstPublishLocationId = msgId
                ));
            }
        }

        if (!cvList.isEmpty()) {
            insert cvList;
            System.debug('Attachments saved: ' + cvList.size());
        }
    }
}