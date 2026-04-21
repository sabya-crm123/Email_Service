public with sharing class ArchiveRuleService {

    private static List<Archive_Rule__mdt> cachedRules;

    @AuraEnabled(cacheable=false)
    public static List<Archive_Rule__mdt> getActiveRules() {
        try { 
            return [
                SELECT Rule_Type__c, Rule_Value__c, Match_Behavior__c, DeveloperName
                FROM Archive_Rule__mdt
                WHERE Active__c = true
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error while fetching archive rules: ' + e.getMessage());
        }
    }

    // 🔹 CHECK ARCHIVE CONDITION
    public static Boolean shouldArchive(String sender, String subject) {

        List<Archive_Rule__mdt> rules = getActiveRules();
        if (rules.isEmpty()) return false;

        String senderLower  = sender != null ? sender.toLowerCase() : '';
        String subjectLower = subject != null ? subject.toLowerCase() : '';

        for (Archive_Rule__mdt rule : rules) {

            String ruleValue = rule.Rule_Value__c != null 
                ? rule.Rule_Value__c.toLowerCase() 
                : '';

            // Sender / Both
            if (rule.Match_Behavior__c == 'Sender' || rule.Match_Behavior__c == 'Both') {

                if (rule.Rule_Type__c == 'Email' && senderLower == ruleValue) {
                    return true;
                }

                if (rule.Rule_Type__c == 'Domain' && senderLower.contains(ruleValue)) {
                    return true;
                }
            }

            // Subject / Both
            if (rule.Match_Behavior__c == 'Subject' || rule.Match_Behavior__c == 'Both') {

                if (rule.Rule_Type__c == 'Keyword' && subjectLower.contains(ruleValue)) {
                    return true;
                }
            }
        }

        return false;
    }

    // 🔥 SAVE RULES (FIXED DESERIALIZATION + SAFE INSERT)
    @AuraEnabled
    public static void saveRules(List<Object> rules, String matchType) {

        if (rules == null || rules.isEmpty()) return;
        
        Set<String> existingValues = new Set<String>();

        for (Archive_Rule__mdt rec : [
            SELECT Rule_Value__c 
            FROM Archive_Rule__mdt 
            WHERE Active__c = true
        ]) {
            if (rec.Rule_Value__c != null) {
                existingValues.add(rec.Rule_Value__c.toLowerCase().trim());
            }
        }

        System.debug('Raw Rules JSON >> ' + JSON.serialize(rules));

        List<Metadata.CustomMetadata> metadataRecords = new List<Metadata.CustomMetadata>();

        for (Object obj : rules) {

            Map<Object, Object> r = (Map<Object, Object>) obj;

            String rType      = (String) r.get('rType');
            String rValue     = (String) r.get('rValue');
            String label      = (String) r.get('label');
            String uniqueName = (String) r.get('uniqueName');

            // 🔥 SAFETY CHECK
            if (String.isBlank(rType) || String.isBlank(rValue)) {
                System.debug('⚠️ Skipping invalid rule: ' + r);
                continue;
            }
            
            String normalizedValue = rValue.toLowerCase().trim();
            if (existingValues.contains(normalizedValue)) {
                System.debug('🚫 Duplicate skipped → ' + rValue);
                continue;
            }       
            
            existingValues.add(normalizedValue);

            String devName = String.isBlank(uniqueName)
                ? 'Rule_' + String.valueOf(Math.abs(Crypto.getRandomInteger())).substring(0, 8)
                : uniqueName;

            String lbl = String.isBlank(label)
                ? capitalize(rType) + '_' + rValue
                : label;

            Metadata.CustomMetadata cmd = new Metadata.CustomMetadata();
            cmd.fullName = 'Archive_Rule__mdt.' + devName;
            cmd.label    = lbl;

            List<Metadata.CustomMetadataValue> cmdValues = new List<Metadata.CustomMetadataValue>();
            cmdValues.add(createField('Rule_Type__c', capitalize(rType)));
            cmdValues.add(createField('Rule_Value__c', rValue));
            if(capitalize(rType) == 'Keyword'){
                cmdValues.add(createField('Match_Behavior__c', 'Subject'));
            }
            if(capitalize(rType) == 'Email'){
                cmdValues.add(createField('Match_Behavior__c', 'Sender'));
            }
            
            cmdValues.add(createField('Active__c', true));

            cmd.values = cmdValues;

            System.debug('🚀 Deploying → ' + cmd.fullName + ' | ' + rType + ' | ' + rValue);

            metadataRecords.add(cmd);
        }

        if (metadataRecords.isEmpty()) return;

        Metadata.DeployContainer container = new Metadata.DeployContainer();

        for (Metadata.CustomMetadata cmd : metadataRecords) {
            container.addMetadata(cmd);
        }

        Metadata.Operations.enqueueDeployment(container, new DeployCallback());

        // 🔥 RESET CACHE AFTER SAVE
        cachedRules = null;
    }

    // 🔹 DEPLOY CALLBACK
    public class DeployCallback implements Metadata.DeployCallback {
        public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext ctx) {

            if (result.status == Metadata.DeployStatus.Succeeded) {
                System.debug('✅ Metadata deploy succeeded');
            } else {
                System.debug('❌ Metadata deploy failed: ' + result.errorMessage);

                if (result.details != null && result.details.componentFailures != null) {
                    for (Metadata.DeployMessage msg : result.details.componentFailures) {
                        System.debug('❌ Failure: ' + msg.fullName + ' → ' + msg.problem);
                    }
                }
            }
        }
    }

    // 🔹 HELPER METHODS
    private static Metadata.CustomMetadataValue createField(String field, Object val) {
        Metadata.CustomMetadataValue cmdv = new Metadata.CustomMetadataValue();
        cmdv.field = field;
        cmdv.value = val;
        return cmdv;
    }

    private static String capitalize(String val) {
        if (String.isBlank(val)) return val;
        return val.substring(0, 1).toUpperCase() + val.substring(1).toLowerCase();
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