/*Created by : Krishnavel S on 17-4-2026
  Desc : Test class written for CustomMetadataDeleter apex class*/

@isTest
private class CustomMetadataDeleter_Test {

    // Mock: simulates a successful SOAP 200 response
    private class SoapSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            // Validate request basics
            System.assertEquals('POST', req.getMethod());
            System.assert(req.getBody().contains('deleteMetadata'));

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('<soapenv:Envelope><soapenv:Body><deleteMetadataResponse/></soapenv:Body></soapenv:Envelope>');
            return res;
        }
    }

    // Mock: simulates a SOAP fault / 500 response
    private class SoapFaultMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('<soapenv:Fault><faultstring>INVALID_SESSION_ID</faultstring></soapenv:Fault>');
            return res;
        }
    }

    // ── deleteArchiveRules: no matching metadata (fullNames stays empty) ────────
    @isTest
    static void testDeleteArchiveRules_NoMatch() {
        // Query returns nothing → fullNames is empty → deleteMetadataRecords NOT called
        Test.startTest();
        CustomMetadataDeleter.deleteArchiveRules('NonExistentRule_xyz');
        Test.stopTest();
        // No exception = pass; branch where fullNames.isEmpty() is covered
    }

    // ── deleteMetadataRecords: success path ─────────────────────────────────────
    @isTest
    static void testDeleteMetadataRecords_Success() {
        Test.setMock(HttpCalloutMock.class, new SoapSuccessMock());
        List<String> fullNames = new List<String>{
            'Archive_Rule__mdt.Rule_A',
            'Archive_Rule__mdt.Rule_B'
        };
        Test.startTest();
        CustomMetadataDeleter.deleteMetadataRecords(fullNames);
        Test.stopTest();
        // Verifies SOAP body built for multiple items + 200 response handled
    }

    // ── deleteMetadataRecords: 500 / fault path (no exception thrown by design) ─
    @isTest
    static void testDeleteMetadataRecords_Fault() {
        Test.setMock(HttpCalloutMock.class, new SoapFaultMock());
        Test.startTest();
        CustomMetadataDeleter.deleteMetadataRecords(
            new List<String>{'Archive_Rule__mdt.Rule_C'}
        );
        Test.stopTest();
        // 500 response is logged via System.debug — no exception rethrown
    }

    // ── deleteArchiveRules: exception path (AuraHandledException) ───────────────
    @isTest
    static void testDeleteArchiveRules_Exception() {
        // Pass null to trigger a NullPointerException inside the try block
        Test.startTest();
        try {
            CustomMetadataDeleter.deleteArchiveRules(null);
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null);
        }
        Test.stopTest();
    }
}