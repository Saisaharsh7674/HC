/**
 * @description Builds and sends the Sales Cloud Daily Health Check email.
 *
 *  Recipients are stored as DATA (editable in Production with no release):
 *    Setup > Custom Settings > Health Check Email Config > Manage (Org Defaults)
 *      - To_Recipients__c  : comma/semicolon separated addresses
 *      - CC_Recipients__c  : comma/semicolon separated addresses
 *  The LWC may also pass per-send overrides (toOverrideCsv / ccOverrideCsv).
 *
 *  The body is rendered from the 'HealthCheck_Summary' Visualforce email
 *  template, which delegates to the HealthCheckEmailBody component. Rendering
 *  via renderStoredEmailTemplate lets us send the template to arbitrary
 *  addresses (no targetObject required).
 */
public with sharing class healthCheckEmailComposer {

    public class EmailConfigException extends Exception {}

    private static final String TEMPLATE_DEV_NAME = 'healthCheckSummary';

    public static void send(Id dailyCheckId) {
        send(dailyCheckId, null, null);
    }

    public static void send(Id dailyCheckId, String toOverrideCsv, String ccOverrideCsv) {
        if (dailyCheckId == null) {
            throw new EmailConfigException('dailyCheckId is required.');
        }

       // List<String> toList = resolve(toOverrideCsv, true);
        //List<String> ccList = resolve(ccOverrideCsv, false);

        /*if (toList.isEmpty()) {
            throw new EmailConfigException(
                'No "To" recipients configured. Set them in Setup > Custom Settings > ' +
                'Health Check Email Config (Org Defaults), or pass them from the UI.');
        }*/
		List<string> toAddress = new List <string>();
        toAddress.add('ssaisaharsh@kpmg.com');
        toAddress.add('skhirit@kpmg.com');
        if (!Test.isRunningTest()) {
            EmailTemplate tmpl = [
                SELECT Id FROM EmailTemplate
                WHERE DeveloperName = :TEMPLATE_DEV_NAME
                LIMIT 1
            ];
            
            OrgWideEmailAddress[] owea = [SELECT Id FROM OrgWideEmailAddress WHERE Address =:System.Label.orgWideEmailAddress];

            Messaging.SingleEmailMessage rendered =
                Messaging.renderStoredEmailTemplate(tmpl.Id, UserInfo.getUserId(), dailyCheckId);

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(toAddress);
            //if (!ccList.isEmpty()) msg.setCcAddresses(ccList);
            msg.setSubject(rendered.getSubject());
            msg.setHtmlBody(rendered.getHtmlBody());
            msg.setSaveAsActivity(false);
            if (owea.size() > 0) {
            msg.setOrgWideEmailAddressId(owea[0].Id);
          }

            Messaging.EmailFileAttachment csv = buildDetailCsv(dailyCheckId);
            if (csv != null) {
                msg.setFileAttachments(new List<Messaging.EmailFileAttachment>{ csv });
            }

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
        }

        update new KPMG_Daily_Health_Check__c(Id = dailyCheckId, KPMG_Email_Sent__c = true);
    }

    private static List<String> resolve(String overrideCsv, Boolean isTo) {
        if (String.isNotBlank(overrideCsv)) return splitAddrs(overrideCsv);
        KPMG_Heath_Check_Email_Config__c cfg = KPMG_Heath_Check_Email_Config__c.getOrgDefaults();
        if (cfg == null) return new List<String>();
        return splitAddrs(isTo ? cfg.KPMG_To_Recipients__c : cfg.KPMG_CC_Recipients__c);
    }

    private static List<String> splitAddrs(String csv) {
        List<String> out = new List<String>();
        if (String.isBlank(csv)) return out;
        for (String p : csv.split('[,;]')) {
            String t = p.trim();
            if (t != '') out.add(t);
        }
        return out;
    }

    /** Builds a CSV of the day's detail rows (null if there are none). */
    private static Messaging.EmailFileAttachment buildDetailCsv(Id dailyCheckId) {
        List<KPMG_Health_Check_Log__c> rows = [
            SELECT KPMG_Section__c, KPMG_Sub_Section__c, KPMG_Status__c,
                   KPMG_Total__c, KPMG_Used__c, KPMG_Remaining__c, KPMG_Details__c
            FROM KPMG_Health_Check_Log__c
            WHERE KPMG_Daily_Health_Check__c = :dailyCheckId
            AND   KPMG_Is_Detail__c = true
            ORDER BY KPMG_Section__c, KPMG_Sub_Section__c
        ];
        if (rows.isEmpty()) return null;

        String csv = 'Section,Item,Status,Total,Used,Remaining,Details\n';
        for (KPMG_Health_Check_Log__c r : rows) {
            csv += q(r.KPMG_Section__c) + ',' + q(r.KPMG_Sub_Section__c) + ',' + q(r.KPMG_Status__c) + ','
                 + q(num(r.KPMG_Total__c)) + ',' + q(num(r.KPMG_Used__c)) + ',' + q(num(r.KPMG_Remaining__c)) + ','
                 + q(r.KPMG_Details__c) + '\n';
        }
        Messaging.EmailFileAttachment a = new Messaging.EmailFileAttachment();
        a.setFileName('HealthCheck_Detail_' + Date.today().format() + '.csv');
        a.setBody(Blob.valueOf(csv));
        a.setContentType('text/csv');
        return a;
    }

    private static String num(Decimal d) { return d == null ? '' : String.valueOf(d); }
    private static String q(String s) {
        if (s == null) return '""';
        return '"' + s.replace('"', '""').replace('\n', ' ').replace('\r', ' ') + '"';
    }
}