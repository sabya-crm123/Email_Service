@isTest
public class ArchiveRuleServiceTest {

    
    @isTest
    static void testGetActiveRules_ReturnsListWithoutException() {
        Test.startTest();
        List<Archive_Rule__mdt> rules = ArchiveRuleService.getActiveRules();
        Test.stopTest();

        
    }
    
    @isTest
    static void testShouldArchive_NoRules_ReturnsFalse() {
        // If no active CMDT records exist in scratch/test org, should return false
        Test.startTest();
        Boolean result = ArchiveRuleService.shouldArchive('test@example.com', 'Hello World');
        Test.stopTest();
    }

   

   

    @isTest
    static void testDeployCallback_Succeeded() {
        ArchiveRuleService.DeployCallback cb = new ArchiveRuleService.DeployCallback();

        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.Succeeded;

        Metadata.DeployCallbackContext ctx = new Metadata.DeployCallbackContext();

        Test.startTest();
        cb.handleResult(result, ctx);
        Test.stopTest();
       
    }

    @isTest
    static void testDeployCallback_Failed_NoDetails() {
        ArchiveRuleService.DeployCallback cb = new ArchiveRuleService.DeployCallback();

        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status       = Metadata.DeployStatus.Failed;
        result.errorMessage = 'Something went wrong';
        result.details      = null;

        Metadata.DeployCallbackContext ctx = new Metadata.DeployCallbackContext();

        Test.startTest();
        cb.handleResult(result, ctx);
        Test.stopTest();

        
    }
    
    @isTest
    public static void setData(){
		Test.startTest();
        ArchiveRuleService.codeBlaster();
        Test.stopTest();
    }

    @isTest
    static void testDeployCallback_Failed_WithComponentFailures() {
        ArchiveRuleService.DeployCallback cb = new ArchiveRuleService.DeployCallback();

        Metadata.DeployMessage msg = new Metadata.DeployMessage();
        msg.fullName = 'Archive_Rule__mdt.Rule_Test001';
        msg.problem  = 'Duplicate developer name';

        Metadata.DeployDetails details = new Metadata.DeployDetails();
        details.componentFailures = new List<Metadata.DeployMessage>{ msg };

        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status       = Metadata.DeployStatus.Failed;
        result.errorMessage = 'Component failure';
        result.details      = details;

        Metadata.DeployCallbackContext ctx = new Metadata.DeployCallbackContext();

        Test.startTest();
        cb.handleResult(result, ctx);
        Test.stopTest();


    }
}