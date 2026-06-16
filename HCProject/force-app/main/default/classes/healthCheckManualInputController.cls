/**
 * @description AuraEnabled controller backing the healthCheckManualInput LWC.
 *
 *  Provides:
 *    - getTodayCheck()           — returns/creates today's master + all log rows
 *    - saveManualLogs()          — saves manual section edits
 *    - sendEmail()               — saves edits + sends the health check email
 *    - runAutomatedChecks()      — re-triggers all automated checkers on demand
 */
public with sharing class healthCheckManualInputController {
 
    // ─── Wire-compatible DTO ──────────────────────────────────────────────────
    public class HealthCheckWrapper {
        @AuraEnabled public KPMG_Daily_Health_Check__c master;
        @AuraEnabled public List<KPMG_Health_Check_Log__c> automatedLogs;
        @AuraEnabled public List<KPMG_Health_Check_Log__c> manualLogs;
        @AuraEnabled public List<ListingSection> listingSections;
        @AuraEnabled public Boolean emailSent;
        @AuraEnabled public String  overallStatus;
    }
 
    // Structured multi-column listing (Scheduled Jobs, Service Accounts, …)
    public class ListingSection {
        @AuraEnabled public String name;
        @AuraEnabled public List<String> headers;
        @AuraEnabled public List<ListingRow> rows;
    }
    public class ListingRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String status;       // RAG (Green/Amber/Red) for colour
        @AuraEnabled public String statusText;   // display word (Good / Not Used / …)
        @AuraEnabled public List<String> cells;
    }
 
    // ─── Get today's check ────────────────────────────────────────────────────
 
    @AuraEnabled(cacheable=false)
    public static HealthCheckWrapper getTodayCheck() {
        KPMG_Daily_Health_Check__c master = getOrCreateMaster();
 
        List<KPMG_Health_Check_Log__c> allLogs = [
            SELECT Id, KPMG_Section__c, KPMG_Sub_Section__c, KPMG_Status__c,
                   KPMG_Total__c, KPMG_Used__c, KPMG_Remaining__c,
                   KPMG_Details__c, KPMG_Comments__c, KPMG_Next_Steps__c,
                   KPMG_Jira_Reference__c, KPMG_Is_Recurring__c,
                   KPMG_Is_Manual__c, KPMG_Is_Pending__c, KPMG_Display_Order__c,
                   KPMG_Run_By__c, KPMG_Image__c
            FROM KPMG_Health_Check_Log__c
            WHERE KPMG_Daily_Health_Check__c = :master.Id
            ORDER BY KPMG_Display_Order__c ASC NULLS LAST, KPMG_Sub_Section__c ASC, CreatedDate Desc
        ];
 
        List<KPMG_Health_Check_Log__c> auto   = new List<KPMG_Health_Check_Log__c>();
        List<KPMG_Health_Check_Log__c> manual = new List<KPMG_Health_Check_Log__c>();
        List<KPMG_Health_Check_Log__c> listing = new List<KPMG_Health_Check_Log__c>();
        Boolean hasRed = false, hasAmber = false;
 
        for (KPMG_Health_Check_Log__c l : allLogs) {
            if (l.KPMG_Run_By__c == 'Listing')      listing.add(l);
            else if (l.KPMG_Is_Manual__c)           manual.add(l);
            else                                    auto.add(l);
            if (l.KPMG_Status__c == 'Red')   hasRed   = true;
            if (l.KPMG_Status__c == 'Amber') hasAmber = true;
        }
 
        HealthCheckWrapper w = new HealthCheckWrapper();
        w.master          = master;
        w.automatedLogs   = auto;
        w.manualLogs      = manual;
        w.listingSections = buildListingSections(listing);
        w.emailSent       = master.KPMG_Email_Sent__c;
        w.overallStatus = hasRed ? 'Red'
                        : hasAmber ? 'Amber'
                        : 'Green';
        return w;
    }
 
    /** Groups 'Listing' logs by section and parses their JSON column payload. */
    private static List<ListingSection> buildListingSections(List<KPMG_Health_Check_Log__c> logs) {
        Map<String, ListingSection> byName = new Map<String, ListingSection>();
        List<String> order = new List<String>();
 
        for (KPMG_Health_Check_Log__c l : logs) {
            String sec = String.isBlank(l.KPMG_Section__c) ? 'Other' : l.KPMG_Section__c;
            ListingSection ls = byName.get(sec);
            if (ls == null) {
                ls = new ListingSection();
                ls.name    = sec;
                ls.headers = new List<String>();
                ls.rows    = new List<ListingRow>();
                byName.put(sec, ls);
                order.add(sec);
            }
 
            List<String> cells = new List<String>();
            if (String.isNotBlank(l.KPMG_Details__c) && l.KPMG_Details__c.startsWith('[')) {
                List<Object> cols = (List<Object>) JSON.deserializeUntyped(l.KPMG_Details__c);
                for (Object o : cols) {
                    Map<String, Object> c = (Map<String, Object>) o;
                    if (ls.headers.size() < cols.size()) {
                        ls.headers.add(String.valueOf(c.get('h')));
                    }
                    cells.add(c.get('v') == null ? '' : String.valueOf(c.get('v')));
                }
            }
            ListingRow r = new ListingRow();
            r.id         = l.Id;
            r.status     = l.KPMG_Status__c;
            r.statusText = String.isBlank(l.KPMG_Comments__c) ? l.KPMG_Status__c : l.KPMG_Comments__c;
            r.cells      = cells;
            ls.rows.add(r);
        }
 
        List<ListingSection> out = new List<ListingSection>();
        for (String n : order) out.add(byName.get(n));
        return out;
    }
 
    // ─── Save manual logs ─────────────────────────────────────────────────────
 
    @AuraEnabled
    public static void saveManualLogs(List<KPMG_Health_Check_Log__c> logs) {
        if (logs == null || logs.isEmpty()) return;
        // Enforce manual flag and clear pending for submitted rows
        for (KPMG_Health_Check_Log__c l : logs) {
            l.KPMG_Is_Manual__c  = true;
            if (l.KPMG_Status__c != 'Pending') {
                l.KPMG_Is_Pending__c = false;
            }
        }
        update logs;
    }
 
    // ─── Save automated logs ──────────────────────────────────────────────────
    //  Lets the reviewer override Status / Details on an automated row without
    //  converting it to a manual row (KPMG_Is_Manual__c stays false, so the row
    //  is still refreshed when automated checks re-run).
 
    @AuraEnabled
    public static void saveAutomatedLogs(List<KPMG_Health_Check_Log__c> logs) {
        if (logs == null || logs.isEmpty()) return;
        for (KPMG_Health_Check_Log__c l : logs) {
            l.KPMG_Is_Manual__c  = false;
            l.KPMG_Is_Pending__c = false;
        }
        update logs;
    }
 
    // ─── Save listing-row status overrides ────────────────────────────────────
    //  Lets the reviewer change the Status on a Scheduled Jobs / Service Accounts
    //  row. The row stays a listing row (KPMG_Run_By__c = 'Listing'); we also sync
    //  KPMG_Comments__c (the word shown on the email pill) to match the new RAG.
 
    @AuraEnabled
    public static void saveListingStatuses(List<KPMG_Health_Check_Log__c> logs) {
        if (logs == null || logs.isEmpty()) return;
        for (KPMG_Health_Check_Log__c l : logs) {
            l.KPMG_Is_Manual__c  = false;
            l.KPMG_Is_Pending__c = false;
            l.KPMG_Comments__c   = listingStatusWord(l.KPMG_Status__c);
        }
        update logs;
    }
 
    private static String listingStatusWord(String rag) {
        if (rag == 'Green')   return 'Good';
        if (rag == 'Amber')   return 'Warning';
        if (rag == 'Red')     return 'Critical';
        if (rag == 'Pending') return 'Pending';
        if (rag == 'N/A')     return 'N/A';
        return rag;
    }
 
    // ─── Send email ───────────────────────────────────────────────────────────
 
    @AuraEnabled
    public static void sendEmail(Id dailyCheckId,
                                  List<KPMG_Health_Check_Log__c> pendingLogs) {
        // First save any unsaved manual entries
        if (pendingLogs != null && !pendingLogs.isEmpty()) {
            saveManualLogs(pendingLogs);
        }
        healthCheckEmailComposer.send(dailyCheckId);
    }
 
    // ─── Re-run automated checks ──────────────────────────────────────────────
 
    @AuraEnabled
    public static void runAutomatedChecks(Id dailyCheckId) {
        healthCheckMasterJob.run();
    }
 
    // ─── Private helpers ──────────────────────────────────────────────────────
 
    private static KPMG_Daily_Health_Check__c getOrCreateMaster() {
        List<KPMG_Daily_Health_Check__c> existing = queryMaster();
        if (!existing.isEmpty()) return existing[0];
 
        // First load of the day: trigger the full run (master + manual
        // placeholders + automated checks). run() is idempotent.
        healthCheckMasterJob.run();
        return queryMaster()[0];
    }
 
    private static List<KPMG_Daily_Health_Check__c> queryMaster() {
        return [
            SELECT Id, KPMG_Check_Date__c, KPMG_Manual_Complete__c,
                   KPMG_Automated_Complete__c, KPMG_Email_Sent__c
            FROM KPMG_Daily_Health_Check__c
            WHERE KPMG_Check_Date__c = TODAY
            LIMIT 1
        ];
    }
}