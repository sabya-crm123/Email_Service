trigger EmailMessage_Trigger on Email_Message__c (after insert) {
	EmailMessageHandler.SetData(Trigger.new);
}