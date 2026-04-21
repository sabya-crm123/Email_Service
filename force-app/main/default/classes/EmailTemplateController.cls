public with sharing class EmailTemplateController {

    public class TemplateWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String content;

        public TemplateWrapper(EmailTemplate et) {
            this.id = et.Id;
            this.name = et.Name;           
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<TemplateWrapper> getEmailTemplates() {

        List<EmailTemplate> templates = [
            SELECT Id, Name
            FROM EmailTemplate
        ];

        List<TemplateWrapper> result = new List<TemplateWrapper>();

        for (EmailTemplate et : templates) {
            result.add(new TemplateWrapper(et));
        }

        return result;
    }
    
    @AuraEnabled
    public static string getTemplateBody(String templateId) {
    
        EmailTemplate et = [
            SELECT Id, Name, HtmlValue
            FROM EmailTemplate
            WHERE Id = :templateId
            LIMIT 1
        ];
    
      	return et.HtmlValue;   
    }
}