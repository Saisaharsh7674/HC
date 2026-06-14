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
        @AuraEnabled public Boolean emailSent;
        @AuraEnabled public String  overallStatus;
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
        Boolean hasRed = false, hasAmber = false;

        for (KPMG_Health_Check_Log__c l : allLogs) {
            if (l.KPMG_Is_Manual__c) manual.add(l); else auto.add(l);
            if (l.KPMG_Status__c == 'Red')   hasRed   = true;
            if (l.KPMG_Status__c == 'Amber') hasAmber = true;
        }

        HealthCheckWrapper w = new HealthCheckWrapper();
        w.master        = master;
        w.automatedLogs = auto;
        w.manualLogs    = manual;
        w.emailSent     = master.KPMG_Email_Sent__c;
        w.overallStatus = hasRed ? 'Red'
                        : hasAmber ? 'Amber'
                        : 'Green';
        return w;
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

    // ─── Send email ───────────────────────────────────────────────────────────

    @AuraEnabled
    public static void sendEmail(Id dailyCheckId,
                                  List<KPMG_Health_Check_Log__c> pendingLogs) {
        // First save any unsaved manual entries
        if (pendingLogs != null && !pendingLogs.isEmpty()) {
            saveManualLogs(pendingLogs);
        }
        //HealthCheck_EmailComposer.send(dailyCheckId);
    }

    // ─── Re-run automated checks ──────────────────────────────────────────────

    @AuraEnabled
    public static void runAutomatedChecks(Id dailyCheckId) {
        healthCheckMasterJob.run();
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static KPMG_Daily_Health_Check__c getOrCreateMaster() {
        List<KPMG_Daily_Health_Check__c> existing = [
            SELECT Id, KPMG_Check_Date__c, KPMG_Manual_Complete__c,
                   KPMG_Automated_Complete__c, KPMG_Email_Sent__c
            FROM KPMG_Daily_Health_Check__c
            WHERE KPMG_Check_Date__c = TODAY
            LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        // Kick off today's full run
         healthCheckMasterJob.run();

        return [
            SELECT Id, KPMG_Check_Date__c, KPMG_Manual_Complete__c,
                   KPMG_Automated_Complete__c, KPMG_Email_Sent__c
            FROM KPMG_Daily_Health_Check__c
            WHERE KPMG_Check_Date__c = TODAY
            LIMIT 1
        ];
    }
}