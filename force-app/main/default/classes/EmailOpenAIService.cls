public with sharing class EmailOpenAIService {
   
    @AuraEnabled(cacheable=false)
    public static String getSummarise(String emailId) {
        Email_Message__c message = [
            SELECT Id, Email_Thread__c, From_Address__c, Body__c, Rich_Text_Body__c,
                   Email_Date__c, To_Address__c, CC_Address_List__c, AI_Summarise_Email__c
            FROM   Email_Message__c
            WHERE  Id = :emailId
            LIMIT  1
        ];
		
        if(message.AI_Summarise_Email__c != null){
            return message.AI_Summarise_Email__c;
        }
        else{
            String prompt = buildPrompt(message);
            AIResponse res = sendPrompt(prompt, message);
    
            if (res.isSuccess) {
                message.AI_Summarise_Email__c = parseAIText(res.responseBody);
                update message;
                return parseAIText(res.responseBody);  
            } else {
                throw new AuraHandledException('AI Error: ' + res.responseBody);
            }
        }
        
    }

    // ─── Build structured prompt ──────────────────────────────────────────────
    private static String buildPrompt(Email_Message__c message) {
        return 'You are an AI assistant inside a Salesforce CRM email inbox. '
             + 'Analyse the email below and respond ONLY with a valid JSON object — no explanation, no markdown, no extra text.\n\n'
             + 'Return exactly this JSON structure:\n'
             + '{\n'
             + '  "overview": "<2-3 sentence plain English summary of what this email is about>",\n'
             + '  "keyPoints": [\n'
             + '    { "label": "<short key point>", "type": "info|warning|success" },\n'
             + '    ...\n'
             + '  ],\n'
             + '  "actionRequired": "<what the recipient needs to do, if anything>",\n'
             + '  "sentiment": "<overall tone e.g. Positive · Professional>",\n'
             + '  "sentimentType": "success|warning|info"\n'
             + '}\n\n'
             + '--- EMAIL ---\n'
             + 'From:    ' + safe(message.From_Address__c)    + '\n'
             + 'To:      ' + safe(message.To_Address__c)      + '\n'
             + 'CC:      ' + safe(message.CC_Address_List__c) + '\n'
             + 'Date:    ' + (message.Email_Date__c != null ? String.valueOf(message.Email_Date__c) : '') + '\n'
             + 'Body:\n'  + safe(message.Rich_Text_Body__c);
    }

    
    private static String parseAIText(String responseBody) {
        try {
            Map<String, Object> root      = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object>        output    = (List<Object>) root.get('output');
            Map<String, Object> firstItem = (Map<String, Object>) output[0];
            List<Object>        content   = (List<Object>) firstItem.get('content');
            Map<String, Object> textBlock = (Map<String, Object>) content[0];
            return (String) textBlock.get('text');   // the raw JSON string from GPT
        } catch (Exception e) {
            throw new AuraHandledException('Failed to parse AI response: ' + e.getMessage());
        }
    }

    
    public static AIResponse sendPrompt(String prompt, Email_Message__c message) {
        AIResponse res = new AIResponse();
        try {
            String bearerToken = System.Label.openAIApiKey;

            Map<String, Object> requestBody = new Map<String, Object>{
                'model' => 'gpt-4o-mini',
                'input' => new List<Object>{
                    new Map<String, Object>{
                        'role'    => 'user',
                        'content' => prompt
                    }
                }
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://api.openai.com/v1/responses');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'Bearer ' + bearerToken);
            req.setTimeout(120000);
            req.setBody(JSON.serialize(requestBody));

            HttpResponse response = new Http().send(req);
            res.statusCode   = response.getStatusCode();
            res.responseBody = response.getBody();
            res.isSuccess    = (response.getStatusCode() == 200);

        } catch (Exception e) {
            res.isSuccess    = false;
            res.responseBody = e.getMessage();
            res.statusCode   = 500;
        }
        return res;
    }

    
    @future(callout=true)
    public static void getSummariseFuture(String emailId) {
        Email_Message__c message = [
            SELECT Id, Email_Thread__c, From_Address__c, Body__c, Rich_Text_Body__c,
                   Email_Date__c, To_Address__c, CC_Address_List__c
            FROM   Email_Message__c
            WHERE  Id = :emailId
            LIMIT  1
        ];

        String prompt = buildPrompt(message);
        AIResponse res = sendPrompt(prompt, message);

        if (res.isSuccess) {
            String summaryJson = parseAIText(res.responseBody);
            System.debug('AI Summary (future): ' + summaryJson);
        } else {
            System.debug('AI Error (future): ' + res.responseBody);
        }
    }
    
    
    @AuraEnabled
    public static String generateReply(String emailId, String userPrompt, String tone) {
    
        Email_Message__c message = [
            SELECT Id, AI_Summarise_Email__c, Last_AI_Reply__c, Display_To_Address__c, Body__c, Rich_Text_Body__c
            FROM Email_Message__c
            WHERE Id = :emailId
            LIMIT 1
        ];
        
       // return message.Last_AI_Reply__c;
    
        /*if (String.isBlank(message.AI_Summarise_Email__c)) {
            throw new AuraHandledException('Summary not found. Please generate summary first.');
        }*/
    
        String instruction = String.isBlank(userPrompt)
            ? 'Make it professional and concise'
            : userPrompt;
    
        String prompt;
        String emailBodySummary = (message.AI_Summarise_Email__c != null ? message.AI_Summarise_Email__c : message.Rich_Text_Body__c);
    
        // 🔥 CASE 1: REFINE EXISTING REPLY
       if (!String.isBlank(message.Last_AI_Reply__c)) {    
            prompt =
                'You are an AI assistant representing Cloud Expert Team.\n\n' +
        
                '### Recipient Info:\n' +
                'Email: ' + message.Display_To_Address__c + '\n' +
                'Extract the person\'s first name from the email address.\n' +
                'Example: john.doe@gmail.com → John\n\n' +
        
                '### Greeting Rule (MANDATORY):\n' +
                '- Ensure the email starts with: Hey <FirstName>\n' +
                '- If name cannot be identified, use: Hey\n\n' +
        
                '### Existing Email Reply (BASE CONTENT):\n' +
                message.Last_AI_Reply__c + '\n\n' +
        
                '### User Instruction (HIGHEST PRIORITY):\n' +
                instruction + '\n\n' +
                
                '### Tone (MANDATORY):\n' +
                '- Write the entire email in a ' + tone + ' tone\n' +
                '- Every sentence must reflect this tone throughout\n\n' +
        
                '### Task:\n' +
                'Refine the email ONLY based on the user instruction.\n\n' +
        
                '### Strict Rules:\n' +
                '- Follow the user instruction EXACTLY\n' +
                '- Modify ONLY the parts required by the instruction\n' +
                '- DO NOT change anything else\n' +
                '- DO NOT rewrite the full email\n' +
                '- Keep original meaning unless instruction says otherwise\n' +
                '- Preserve structure, flow, and content\n' +
                '- Do NOT include Subject line\n' +
                '- Output ONLY the final email\n' +
                '- Improve clarity and tone as per the Tone section above\n' +
                '- Format output as HTML using <p> and <br> and do not give <html> at starting\n\n' +
        
                '### Signature (MANDATORY - KEEP OR ADD IF MISSING):\n' +
                'Cloud Expert Team\n' +
                'crm@cloudexpertsindia.com';
        }else {

            prompt =
                'You are an AI assistant representing Cloud Expert Team.\n\n' +
        
                '### Recipient Info:\n' +
                'Email: ' + message.Display_To_Address__c + '\n' +
                'Extract the person\'s first name from the email address.\n' +
                'Example: john.doe@gmail.com → John\n\n' +
        
                '### Greeting Rule (MANDATORY):\n' +
                '- Start the email with: Hey <FirstName>\n' +
                '- If name cannot be identified, use: Hey\n\n' +
        
                '### Email Summary/Body:\n' + 
                 emailBodySummary + '\n\n' +
        
                '### User Instruction:\n' +
                instruction + '\n\n' +
                
                '### Tone (MANDATORY):\n' +
                '- Write the entire email in a ' + tone + ' tone\n' +
                '- Every sentence must reflect this tone throughout\n\n' +
        
                '### Task:\n' +
                'Generate a professional email reply.\n\n' +
        
                '### Rules:\n' +
                '- Keep the meaning same unless user asks to change\n' +
                '- Improve clarity and tone as per the Tone section above\n' +
                '- Do NOT add unnecessary content\n' +
                '- Do NOT include Subject line\n' +  
                '- Output only the updated reply\n' +
                '- Format output as HTML using <br> for line breaks and <p> for paragraphs and do not give <html> at starting\n\n' +
        
                '### Signature (MANDATORY):\n' +
                'Cloud Expert Team\n' +
                'crm@cloudexpertsindia.com';
        }
    
        AIResponse res = sendPrompt(prompt, message);
    
        if (res.isSuccess) {
            String reply = parseAIText(res.responseBody);
    
            // 🔥 SAVE LAST REPLY
            message.Last_AI_Reply__c = reply;
            update message;
    
            return reply;
    
        } else {
            throw new AuraHandledException(res.responseBody);
        }
    }

    
    private static String safe(String val) {
        return String.isBlank(val) ? '' : val;
    }

   
    public class AIResponse {
        public Integer statusCode;
        public String  responseBody;
        public Boolean isSuccess;
    }
}