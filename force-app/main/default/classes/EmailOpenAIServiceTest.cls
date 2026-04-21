@isTest
private class EmailOpenAIServiceTest {

    class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"output":[{"content":[{"text":"{\\"overview\\":\\"Test summary\\",\\"keyPoints\\":[{\\"label\\":\\"Point1\\",\\"type\\":\\"info\\"}],\\"actionRequired\\":\\"None\\",\\"sentiment\\":\\"Positive\\",\\"sentimentType\\":\\"success\\"}"}]}]}');
            return res;
        }
    }

    @isTest
    static void testGetSummarise() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        Email_Message__c msg = new Email_Message__c(
            From_Address__c = 'test@test.com',
            To_Address__c = 'to@test.com',
            Body__c = 'This is test email',
            Email_Date__c = System.now()
        );
        insert msg;

        Test.startTest();
        EmailOpenAIService.getSummarise(msg.Id);
        Test.stopTest();
    }

    @isTest
    static void testGenerateReply() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        Email_Message__c msg = new Email_Message__c(
            From_Address__c = 'test@test.com',
            To_Address__c = 'to@test.com',
            Body__c = 'Test body',
            Email_Date__c = System.now(),
            AI_Summarise_Email__c = 'Summary present'
        );
        insert msg;

        Test.startTest();
        EmailOpenAIService.generateReply(msg.Id, 'Make it short', 'professional');
        Test.stopTest();
    }

    @isTest
    static void testGenerateReplyRefine() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        Email_Message__c msg = new Email_Message__c(
            From_Address__c = 'test@test.com',
            To_Address__c = 'to@test.com',
            Body__c = 'Test body',
            Email_Date__c = System.now(),
            AI_Summarise_Email__c = 'Summary present',
            Last_AI_Reply__c = 'Old reply'
        );
        insert msg;

        Test.startTest();
        EmailOpenAIService.generateReply(msg.Id, 'Improve tone', 'professional');
        Test.stopTest();
    }

    @isTest
    static void testFutureMethod() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        Email_Message__c msg = new Email_Message__c(
            From_Address__c = 'test@test.com',
            To_Address__c = 'to@test.com',
            Body__c = 'Future test',
            Email_Date__c = System.now()
        );
        insert msg;

        Test.startTest();
        EmailOpenAIService.getSummariseFuture(msg.Id);
        Test.stopTest();
    }
}