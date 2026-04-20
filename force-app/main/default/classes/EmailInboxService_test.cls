@isTest
public class EmailInboxService_test {
	@isTest
    public static void setData(){
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User testUser = new User(
            FirstName        = 'Test',
            LastName         = 'User',
            Email            = 'testuser@example.com',
            Username         = 'testuser' + DateTime.now().getTime() + '@example.com',
            Alias            = 'tuser',
            TimeZoneSidKey   = 'America/New_York',
            LocaleSidKey     = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId        = adminProfile.Id
        );
        insert testUser;
        
		Email_Thread__c et = new Email_Thread__c();
        et.Subject__c = 'Test';
        et.OwnerId = testUser.Id;
        et.Email_Status__c = 'Active';
        insert et;
        
        Email_Message__c em = new Email_Message__c();
        em.Email_Thread__c = et.Id;
        em.CC_Address__c  = 'zyz@gmail.com';
        em.From_Address__c = 'abc@gmail.com';
        em.Message_ID__c = '123';
        em.Body__c = 'test';    
        em.OwnerId = testUser.Id;
        insert em;
        
        Email_Message__c em1 = new Email_Message__c();
        em1.Email_Thread__c = et.Id;
        em1.CC_Address__c  = 'zyz@gmail.com';
        em1.From_Address__c = UserInfo.getUserEmail();
        em1.Message_ID__c = '123';
        em1.Body__c = 'test';   
        em1.OwnerId = testUser.Id;
        insert em1;
        
        Test.startTest();
        EmailInboxService.getThreads(0, 20, testUser.Id, 'unarchived');
        EmailInboxService.getThreadMessages(et.Id, 0, 20, testUser.Id);       
        
        List<String> toAddresses = new List<String>{'shreyash@gmail.com', 'fox@fill.com'};
        
		String subject = 'Payment received';
        String body = 'with all due agreements we recieved your payment';
        List<String> fileNames = new List<String>{'AAA', 'BBB'};
        List<String> fileContents = new List<String>{'Hello aaa', 'hello bbb'};
        List<String> contType = new List<String>{'txt', 'txt'};
            
        EmailInboxService.sendEmail('shreyash@gmail.com', 'test@gmail.com' , 'test1@gmail.com', subject, body, fileNames, fileContents, contType);
        EmailInboxService.getSentThreads('Active', testUser.Id);
        EmailInboxService.sendReplyEmail('shreyash@gmail.com', 'test@gmail.com' , subject, body, em1.Id, fileNames, fileContents, contType);
        EmailInboxService.deleteMessage('delete', et.Id);
        Test.stopTest();
    }
}