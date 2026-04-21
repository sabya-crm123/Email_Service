public class EmailMessageHandler {
    public static void SetData(List<Email_Message__c> messageRecord){
        
        List<Email_Thread__c> emailThreadList = new List<Email_Thread__c>();
        
        for(Email_Message__c em : messageRecord){            
            if(em.Email_Thread__c != null){
                Email_Thread__c et = new Email_Thread__c();
                et.Id = em.Email_Thread__c;
                et.Last_Email_Message__c = DateTime.now();
                emailThreadList.add(et);
            }          
           
        }
        
        if(!emailThreadList.isEmpty()){
            update emailThreadList;
        }
    }
}