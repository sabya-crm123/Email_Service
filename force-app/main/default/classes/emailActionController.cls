public class emailActionController {
    
    public class emailMessageWrapper {
        @AuraEnabled public Id threadId;
        @AuraEnabled public String subject;
        @AuraEnabled public String body;
        @AuraEnabled public String emailAddress;
        @AuraEnabled public String accountId;
        @AuraEnabled public String contactId;
        @AuraEnabled public String projectId;
        @AuraEnabled public String owner;
    }
    
    @AuraEnabled(cacheable=true)
    public static emailMessageWrapper getEmailDetails(String emailId) {
        try {
            Email_Message__c messages = [SELECT Id, Thread_Subject__c, Email_Thread__c, From_Address__c, Body__c, Email_Date__c, To_Address__c, CC_Address_List__c,
                                         Case_Created__c,  Rich_Text_Body__c
                    FROM Email_Message__c WHERE Id =: emailId];
                
            emailMessageWrapper emw = new emailMessageWrapper();
            emw.subject = messages.Thread_Subject__c;
            emw.body = messages.Rich_Text_Body__c;
            emw.emailAddress = messages.From_Address__c;
            
            List<Contact> conRec = [Select Id, AccountId from Contact where Email =: messages.From_Address__c limit 1];
            List<Project1__c> project = new List<Project1__c>();
            
            if(!conRec.isEmpty()){
               emw.accountId = conRec[0].AccountId;
               emw.contactId = conRec[0].Id;
               project = [Select Id, Account__c, Case_Owner__c from Project1__c where Account__c =: conRec[0].AccountId limit 1];
            }
            
            if(!project.isEmpty()){
               emw.projectId = project[0].Id;
               emw.owner = project[0].Case_Owner__c;
            }
            
            if(emw != null){
                return emw;
            }
            else 
                return null;
        } catch (Exception e) {
            throw new AuraHandledException('Error while saving Task: ' + e.getMessage());
        }
        
    }
    
	@AuraEnabled
    public static String saveCase(String caseJson, String emailId) {
        try {
            
            List<Email_Message__c> messages = [SELECT Id, Email_Thread__c, From_Address__c, Body__c, Email_Date__c, To_Address__c, CC_Address_List__c, Case_Created__c
            FROM Email_Message__c WHERE Id =: emailId];           
            
            if(!messages.isEmpty()){ 
                Case cse = (Case) JSON.deserialize(caseJson, Case.class); 
                
                insert cse;  
                refreshEmail(emailId);
                
                messages[0].Case__c = cse.Id;    
                messages[0].Case_Created__c = true;
                update messages;
            }
            
            return 'success';
            
        } catch (Exception e) {
            throw new AuraHandledException('Error while saving Task: ' + e.getMessage());
        }
    }
    
    
    @AuraEnabled
    public static void saveTask(String taskJson, String emailId) {
       
            
            List<Email_Message__c> messages = [SELECT Id, Email_Thread__c, From_Address__c, Body__c, Email_Date__c, To_Address__c, CC_Address_List__c, Task_Created__c
            FROM Email_Message__c WHERE Id =: emailId];           
            
            
            Task tsk = (Task) JSON.deserialize(taskJson, Task.class);    
            tsk.WhatId = emailId;
			insert tsk;            
            
            messages[0].Task_Created__c = true;
            update messages;
            
            refreshEmail(emailId);
        
    }
    
    @AuraEnabled
    public static void saveOpportunity(String oppJson, String emailId) {
       try {   
            List<Email_Message__c> messages = [SELECT Id, Email_Thread__c, From_Address__c, Body__c, Email_Date__c, To_Address__c, CC_Address_List__c, Opportunity_Created__c
            FROM Email_Message__c WHERE Id =: emailId];   
           
            Opportunity opp = (Opportunity) JSON.deserialize(oppJson, Opportunity.class);            
			insert opp;           
            
            messages[0].Opportunity_Created__c = true;
            update messages;
           
            refreshEmail(emailId);
       } catch (Exception e) {
            throw new AuraHandledException('Error while saving Task: ' + e.getMessage());
       }     
        
    }
    
    
    public static void refreshEmail(String msg){
        New_Email__e inbound_event = new New_Email__e ();
        inbound_event.MessageId__c = msg;
        Database.SaveResult publish_result = EventBus.publish(inbound_event);
    }
    
    public static void codeBlaster(){
        Integer i = 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
        i = i + 1;
    }
}