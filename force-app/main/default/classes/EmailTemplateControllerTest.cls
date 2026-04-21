@isTest
public class EmailTemplateControllerTest {

    @isTest
    static void testGetEmailTemplates() {

        EmailTemplate et = new EmailTemplate(
            Name = 'Test Template',
            DeveloperName = 'Test_Template',
            FolderId = UserInfo.getUserId(),
            TemplateType = 'text',
            Subject = 'Test Subject',
            Body = 'Test Body',
            IsActive = true
        );

        insert et;

        Test.startTest();
        EmailTemplateController.getEmailTemplates();
        Test.stopTest();
    }

    @isTest
    static void testGetTemplateBody() {

        EmailTemplate et = new EmailTemplate(
            Name = 'Test Template 2',
            DeveloperName = 'Test_Template_2',
            FolderId = UserInfo.getUserId(),
            TemplateType = 'text', // 🔥 FIXED
            Subject = 'Test Subject',
            Body = 'Test Body',
            IsActive = true
        );

        insert et;

        Test.startTest();
        EmailTemplateController.getTemplateBody(et.Id);
        Test.stopTest();
    }
}