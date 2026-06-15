/**
 * @description Builds and sends the Sales Cloud Daily Health Check email.
 *
 *  Recipients are read dynamically from the hierarchy Custom Setting
 *  KPMG_Heath_Check_Email_Config__c (Org Defaults), so they can be changed in
 *  Production with no release:
 *      KPMG_To_Recipients__c  - comma/semicolon separated To addresses
 *      KPMG_CC_Recipients__c  - comma/semicolon separated CC addresses
 *
 *  The body is rendered from the 'healthCheckSummary' Visualforce email
 *  template (delegates to the healthCheckEmailBody component) and sent through
 *  the Org-Wide Email Address named in the orgWideEmailAddress custom label.
 */
public with sharing class healthCheckEmailComposer {
 
    public class EmailConfigException extends Exception {}
 
    private static final String TEMPLATE_DEV_NAME = 'healthCheckSummary';
 
    public static void send(Id dailyCheckId) {
        if (dailyCheckId == null) {
            throw new EmailConfigException('dailyCheckId is required.');
        }
 
        KPMG_Heath_Check_Email_Config__c cfg = KPMG_Heath_Check_Email_Config__c.getOrgDefaults();
        List<String> toList = splitAddrs(cfg == null ? null : cfg.KPMG_To_Recipients__c);
        List<String> ccList = splitAddrs(cfg == null ? null : cfg.KPMG_CC_Recipients__c);
 
        if (toList.isEmpty()) {
            throw new EmailConfigException(
                'No "To" recipients configured. Set them in Setup > Custom Settings > ' +
                'Heath Check Email Config (Manage > Org Defaults > KPMG_To_Recipients__c).');
        }
 
       // if (!Test.isRunningTest()) {
            EmailTemplate tmpl = [
                SELECT Id FROM EmailTemplate
                WHERE DeveloperName = :TEMPLATE_DEV_NAME
                LIMIT 1
            ];
 
            OrgWideEmailAddress[] owea = [
                SELECT Id FROM OrgWideEmailAddress
                WHERE Address = :System.Label.orgWideEmailAddress
            ];
 
            Messaging.SingleEmailMessage rendered =
                Messaging.renderStoredEmailTemplate(tmpl.Id, UserInfo.getUserId(), dailyCheckId);
 
            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(toList);
            if (!ccList.isEmpty()) {
                msg.setCcAddresses(ccList);
            }
            msg.setSubject(rendered.getSubject());
            msg.setHtmlBody(rendered.getHtmlBody());
            msg.setSaveAsActivity(false);
            if (!owea.isEmpty()) {
                msg.setOrgWideEmailAddressId(owea[0].Id);
            }
 
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
       // }
 
        update new KPMG_Daily_Health_Check__c(Id = dailyCheckId, KPMG_Email_Sent__c = true);
    }
 
    /** Splits a comma/semicolon separated address string into a trimmed list. */
    private static List<String> splitAddrs(String csv) {
        List<String> out = new List<String>();
        if (String.isBlank(csv)) return out;
        for (String p : csv.split('[,;]')) {
            String t = p.trim();
            if (t != '') out.add(t);
        }
        return out;
    }
}