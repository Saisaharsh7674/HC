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
 
        if (!Test.isRunningTest()) {
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
 
            // The Outlook desktop/mobile apps block remote images by default AND
            // can't render base64 "data:" images, and Apex can't set a Content-ID
            // (so cid inline only works in lenient webmail). The ONE method that
            // shows screenshots reliably in every client incl. the Outlook app is
            // real FILE ATTACHMENTS. We always attach each embedded screenshot, and
            // — best effort — also rewrite the inline <img> to a public HTTPS URL so
            // permissive clients (Gmail, Apple Mail, Outlook web) still show it inline.
            List<Messaging.EmailFileAttachment> imgAttachments =
                new List<Messaging.EmailFileAttachment>();
            String htmlBody = prepareEmailImages(rendered.getHtmlBody(), imgAttachments);
 
            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(toList);
            if (!ccList.isEmpty()) {
                msg.setCcAddresses(ccList);
            }
            msg.setSubject(rendered.getSubject());
            msg.setHtmlBody(htmlBody);
            if (!imgAttachments.isEmpty()) {
                msg.setFileAttachments(imgAttachments);
            }
            msg.setSaveAsActivity(false);
            if (!owea.isEmpty()) {
                msg.setOrgWideEmailAddressId(owea[0].Id);
            }
 
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
        }
 
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
 
    // Public-link lifetime for the best-effort inline copy (days).
    private static final Integer LINK_EXPIRY_DAYS = 365;
    // Best-effort inline rendering via public ContentDistribution URLs.
    // Set false to skip public links entirely (attachments only — most private).
    private static final Boolean ENABLE_INLINE_HOSTING = true;
 
    /**
     * Handles the base64 screenshots that lightning-input-rich-text embeds.
     *
     *  ALWAYS: attaches each screenshot as a real file (setInline(false)) so it
     *          opens reliably in every client, including the Outlook app.
     *  BODY:   removes the embedded <img> (which renders as a broken "X" in the
     *          Outlook app) and replaces the WHOLE tag with either a clickable
     *          "View Screenshot" link to the public file (when Content Deliveries
     *          is available) or a small "(see attachment)" note. No broken image.
     *
     * Returns the rewritten HTML and populates `attachments`.
     */
    @TestVisible
    private static String prepareEmailImages(String html,
            List<Messaging.EmailFileAttachment> attachments) {
        if (String.isBlank(html)) return html;
 
        // Match the WHOLE <img ...> tag whose src is a base64 data: image.
        Matcher m = Pattern.compile(
            '(?i)<img\\b[^>]*?src\\s*=\\s*"(data:image/([a-zA-Z0-9.+-]+);base64,[^"]+)"[^>]*>'
        ).matcher(html);
 
        List<String> tagOrder = new List<String>();          // distinct full <img> tags
        Map<String, Integer> tagIndex = new Map<String, Integer>();
        List<Blob>   bodies = new List<Blob>();
        List<String> exts   = new List<String>();
        Integer idx = 0;
 
        while (m.find()) {
            String fullTag = m.group(0);
            if (tagIndex.containsKey(fullTag)) continue;
            String dataUri = m.group(1);
            String ext     = m.group(2).toLowerCase();
            try {
                Blob body = EncodingUtil.base64Decode(dataUri.substringAfter('base64,'));
                String fileName = 'Health Check Screenshot ' + (idx + 1)
                                + '.' + (ext == 'jpeg' ? 'jpg' : ext);
 
                Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
                efa.setFileName(fileName);
                efa.setContentType('image/' + ext);
                efa.setInline(false);
                efa.setBody(body);
                attachments.add(efa);
 
                tagIndex.put(fullTag, idx);
                tagOrder.add(fullTag);
                bodies.add(body);
                exts.add(ext);
                idx++;
            } catch (Exception ex) {
                // Undecodable — leave the tag alone (nothing to attach).
            }
        }
        if (tagOrder.isEmpty()) return html;
 
        // Best-effort: host each image so we can offer a clickable view link.
        List<String> linkByIndex = new List<String>();
        for (Integer i = 0; i < tagOrder.size(); i++) linkByIndex.add(null);
 
        if (ENABLE_INLINE_HOSTING) {
            try {
                List<ContentVersion> versions = new List<ContentVersion>();
                for (Integer i = 0; i < tagOrder.size(); i++) {
                    versions.add(new ContentVersion(
                        Title        = 'HC Email Image ' + (i + 1),
                        PathOnClient = 'hcimg' + (i + 1) + '.' + (exts[i] == 'jpeg' ? 'jpg' : exts[i]),
                        VersionData  = bodies[i]
                    ));
                }
                insert versions;
 
                List<ContentDistribution> dists = new List<ContentDistribution>();
                for (Integer i = 0; i < versions.size(); i++) {
                    dists.add(new ContentDistribution(
                        Name                             = 'HC Email Image ' + (i + 1),
                        ContentVersionId                 = versions[i].Id,
                        PreferencesAllowViewInBrowser    = true,
                        PreferencesAllowOriginalDownload = true,
                        PreferencesPasswordRequired      = false,
                        PreferencesNotifyOnVisit         = false,
                        ExpiryDate                       = Date.today().addDays(LINK_EXPIRY_DAYS)
                    ));
                }
                insert dists;
 
                Map<Id, String> urlByVersion = new Map<Id, String>();
                for (ContentDistribution cd : [
                    SELECT ContentVersionId, DistributionPublicUrl, ContentDownloadUrl
                    FROM ContentDistribution WHERE Id IN :dists
                ]) {
                    String u = String.isNotBlank(cd.DistributionPublicUrl)
                        ? cd.DistributionPublicUrl : cd.ContentDownloadUrl;
                    urlByVersion.put(cd.ContentVersionId, u);
                }
                for (Integer i = 0; i < versions.size(); i++) {
                    linkByIndex[i] = urlByVersion.get(versions[i].Id);
                }
            } catch (Exception hostEx) {
                // Content Deliveries unavailable — fall back to the "(attached)" note.
            }
        }
 
        // Swap each broken <img> tag for a link (or note); the file is attached.
        String out = html;
        for (String tag : tagOrder) {
            Integer i = tagIndex.get(tag);
            String label = 'Screenshot ' + (i + 1);
            String replacement = String.isNotBlank(linkByIndex[i])
                ? '<a href="' + linkByIndex[i] + '" target="_blank" '
                  + 'style="color:#1c5fbf; font-weight:bold; text-decoration:underline;">View '
                  + label + '</a>'
                : '<span style="color:#6b7280; font-style:italic;">' + label + ' (see attachment)</span>';
            out = out.replace(tag, replacement);
        }
        return out;
    }
}