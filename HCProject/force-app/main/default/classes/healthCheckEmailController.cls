/**
 * @description Controller for the HealthCheckEmailBody Visualforce component.
 *              Loads the day's logs and arranges them into:
 *                - summary bands (one row per item, shown in the email body)
 *                - detail groups (per-line breakdown, shown in the appendix)
 *              A log row is "detail" when KPMG_Is_Detail__c = true; it links to
 *              its summary item via KPMG_Parent_Item__c.
 */
public with sharing class healthCheckEmailController {
 
    public Id dailyCheckId { get; set; }
 
    private static final List<String> BAND_ORDER = new List<String>{
        'Sales Cloud Integrations', 'Process', 'Sources/Items'
    };
 
    private List<SectionWrap> sections;
    private List<DetailWrap>  detailGroups;
    private KPMG_Daily_Health_Check__c masterRec;
 
    public KPMG_Daily_Health_Check__c getMaster() { build(); return masterRec; }
    public List<SectionWrap> getSections()        { build(); return sections; }
    public List<DetailWrap>  getDetailGroups()    { build(); return detailGroups; }
 
    public String getCheckDate() {
        build();
        if (masterRec != null && masterRec.KPMG_Check_Date__c != null) {
            return masterRec.KPMG_Check_Date__c.format();
        }
        return Date.today().format();
    }
 
    /** Footer timestamp, e.g. "6/15/2026 6:02 PM". */
    public String getGeneratedLabel() {
        return System.now().format('M/d/yyyy h:mm a');
    }
 
    /** First-column header noun for a section band. */
    private static String columnLabelFor(String band) {
        if (band == HealthCheck_Constants.SEC_INTEGRATIONS) return 'Integration';
        if (band == HealthCheck_Constants.SEC_PROCESS)      return 'Process';
        if (band == HealthCheck_Constants.SEC_USER_LIC)     return 'User License';
        if (band == HealthCheck_Constants.SEC_PSL)          return 'Permission Set License';
        return 'Item';
    }
 
    private void build() {
        if (sections != null) return;
        sections = new List<SectionWrap>();
        detailGroups = new List<DetailWrap>();
        if (dailyCheckId == null) return;
 
        masterRec = [
            SELECT Id, KPMG_Check_Date__c
            FROM KPMG_Daily_Health_Check__c
            WHERE Id = :dailyCheckId
            LIMIT 1
        ];
 
        List<KPMG_Health_Check_Log__c> logs = [
            SELECT Id, KPMG_Section__c, KPMG_Sub_Section__c, KPMG_Status__c,
                   KPMG_Total__c, KPMG_Used__c, KPMG_Remaining__c,
                   KPMG_Details__c, KPMG_Comments__c, KPMG_Next_Steps__c,
                   KPMG_Is_Recurring__c, KPMG_Image__c,
                   KPMG_Is_Detail__c, KPMG_Parent_Item__c, KPMG_Display_Order__c
            FROM KPMG_Health_Check_Log__c
            WHERE KPMG_Daily_Health_Check__c = :dailyCheckId
            ORDER BY KPMG_Display_Order__c NULLS LAST, KPMG_Sub_Section__c
        ];
 
        Map<String, SectionWrap> bandMap   = new Map<String, SectionWrap>();
        Map<String, DetailWrap>  detailMap = new Map<String, DetailWrap>();
        List<String> detailOrder = new List<String>();
 
        for (KPMG_Health_Check_Log__c l : logs) {
            if (l.KPMG_Is_Detail__c == true) {
                String key = String.isBlank(l.KPMG_Parent_Item__c)
                    ? l.KPMG_Sub_Section__c : l.KPMG_Parent_Item__c;
                DetailWrap dw = detailMap.get(key);
                if (dw == null) {
                    dw = new DetailWrap();
                    dw.itemLabel = key;
                    dw.section   = l.KPMG_Section__c;
                    dw.rows      = new List<RowWrap>();
                    detailMap.put(key, dw);
                    detailOrder.add(key);
                }
                dw.rows.add(new RowWrap(l));
            } else {
                String band = String.isBlank(l.KPMG_Section__c) ? 'Other' : l.KPMG_Section__c;
                SectionWrap sw = bandMap.get(band);
                if (sw == null) {
                    sw = new SectionWrap();
                    sw.name     = band;
                    sw.colLabel = columnLabelFor(band);
                    sw.rows = new List<RowWrap>();
                    bandMap.put(band, sw);
                }
                sw.rows.add(new RowWrap(l));
            }
        }
 
        for (String b : BAND_ORDER) {
            if (bandMap.containsKey(b)) { sections.add(bandMap.get(b)); bandMap.remove(b); }
        }
        for (SectionWrap sw : bandMap.values()) sections.add(sw);
        for (String k : detailOrder) detailGroups.add(detailMap.get(k));
    }
 
    public class SectionWrap {
        public String name { get; set; }
        public String colLabel { get; set; }
        public List<RowWrap> rows { get; set; }
    }
    public class DetailWrap {
        public String itemLabel { get; set; }
        public String section { get; set; }
        public List<RowWrap> rows { get; set; }
    }
 
    public class RowWrap {
        public KPMG_Health_Check_Log__c log { get; set; }
        public RowWrap(KPMG_Health_Check_Log__c l) { this.log = l; }
 
        public String getLabel()     { return log.KPMG_Sub_Section__c; }
        public String getStatus()    { return log.KPMG_Status__c; }
        public String getComments()  { return toHtml(log.KPMG_Details__c, log.KPMG_Comments__c); }
        public String getNextSteps() { return brk(log.KPMG_Next_Steps__c); }
        public String getRecurring() { return log.KPMG_Is_Recurring__c == true ? 'Yes' : ''; }
        public String getImageHtml() { return log.KPMG_Image__c == null ? '' : log.KPMG_Image__c; }
        public String getTotal()     { return fmt(log.KPMG_Total__c); }
        public String getUsed()      { return fmt(log.KPMG_Used__c); }
        public String getRemaining() { return fmt(log.KPMG_Remaining__c); }
 
        /** Friendly label shown on the status pill (RAG -> business wording). */
        public String getStatusLabel() {
            String s = log.KPMG_Status__c == null ? '' : log.KPMG_Status__c.toUpperCase();
            if (s == 'GREEN')   return 'Healthy';
            if (s == 'AMBER')   return 'Warning';
            if (s == 'RED')     return 'Critical';
            if (s == 'PENDING') return 'Pending';
            if (s == 'N/A')     return 'N/A';
            return String.isBlank(log.KPMG_Status__c) ? '—' : log.KPMG_Status__c;
        }
 
        /** Small glyph rendered inside the pill (email-safe Unicode). */
        public String getStatusIcon() {
            String s = log.KPMG_Status__c == null ? '' : log.KPMG_Status__c.toUpperCase();
            if (s == 'GREEN')   return '&#10003;';   // check
            if (s == 'AMBER')   return '&#9888;';    // warning
            if (s == 'RED')     return '&#10007;';   // cross
            if (s == 'PENDING') return '&#9203;';    // hourglass
            return '';
        }
 
        /** Complete inline style for the rounded status pill. */
        public String getBadgeStyle() {
            String base = 'display:inline-block; padding:3px 10px; border-radius:12px; '
                        + 'font-weight:bold; font-size:11px; white-space:nowrap; ';
            String s = log.KPMG_Status__c == null ? '' : log.KPMG_Status__c.toUpperCase();
            if (s == 'GREEN')   return base + 'background:#1e8e4f; color:#ffffff;';
            if (s == 'AMBER')   return base + 'background:#fff3d6; color:#9a6700; border:1px solid #e6b800;';
            if (s == 'RED')     return base + 'background:#e0322f; color:#ffffff;';
            if (s == 'PENDING') return base + 'background:#fff3d6; color:#9a6700; border:1px solid #e6b800;';
            return base + 'background:#e8eaed; color:#555555;';
        }
 
        private String fmt(Decimal d) { return d == null ? '—' : d.format(); }
        private String brk(String s)  { return s == null ? '' : s.replace('\n', '<br/>'); }
        private String toHtml(String a, String b) {
            List<String> parts = new List<String>();
            if (String.isNotBlank(a)) parts.add(a.trim());
            if (String.isNotBlank(b)) parts.add(b.trim());
            return brk(String.join(parts, '\n\n'));
        }
    }
}