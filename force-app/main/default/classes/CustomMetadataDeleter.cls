public class CustomMetadataDeleter {
	
    @AuraEnabled(cacheable=false)
    public static void deleteArchiveRules(String developerName) {
        try { 
            List<String> fullNames = new List<String>();
            for (Archive_Rule__mdt rec : [SELECT DeveloperName FROM Archive_Rule__mdt where DeveloperName =: developerName]) {
                fullNames.add('Archive_Rule__mdt.' + rec.DeveloperName);
            }
            if (!fullNames.isEmpty()) {
                deleteMetadataRecords(fullNames);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error while fetching archive rules: ' + e.getMessage());
        }
    }

    @future(callout=true)
    public static void deleteMetadataRecords(List<String> fullNames) {
        try { 
            String sessionId = UserInfo.getSessionId();
            String metadataUrl = URL.getOrgDomainUrl().toExternalForm() 
                               + '/services/Soap/m/59.0';
    
            // Build <items> nodes
            String itemsXml = '';
            for (String fullName : fullNames) {
                itemsXml += '<met:items>' + fullName + '</met:items>';
            }
    
            String soapBody = '<?xml version="1.0" encoding="UTF-8"?>'
                + '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" '
                + '  xmlns:met="http://soap.sforce.com/2006/04/metadata">'
                + '  <soapenv:Header>'
                + '    <met:CallOptions><met:client>apex</met:client></met:CallOptions>'
                + '    <met:SessionHeader>'
                + '      <met:sessionId>' + sessionId + '</met:sessionId>'
                + '    </met:SessionHeader>'
                + '  </soapenv:Header>'
                + '  <soapenv:Body>'
                + '    <met:deleteMetadata>'
                + '      <met:type>CustomMetadata</met:type>'
                +        itemsXml
                + '    </met:deleteMetadata>'
                + '  </soapenv:Body>'
                + '</soapenv:Envelope>';
    
            HttpRequest req = new HttpRequest();
            req.setEndpoint(metadataUrl);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'text/xml');
            req.setHeader('SOAPAction', 'deleteMetadata');
            req.setBody(soapBody);
    
            HttpResponse res = new Http().send(req);
            System.debug('Status: ' + res.getStatusCode());
            System.debug('Body: ' + res.getBody());
        
        } catch (Exception e) {
            throw new AuraHandledException('Error while fetching archive rules: ' + e.getMessage());
        }
    }
}