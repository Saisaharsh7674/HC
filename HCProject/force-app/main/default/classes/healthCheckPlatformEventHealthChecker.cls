/**
 * @description  Hourly Platform Event check (Schedulable + Batch).
 *
 *  This class runs ONLY Platform Event related checks every hour by
 *  delegating execution to the unified healthCheckRunner engine.
 *
 *  It does not contain any business logic — everything is metadata-driven.
 *
 *  Schedule once:
 *      System.schedule('PE Health Check Hourly',
 *                      '0 0 * * * ?', new healthCheckPlatformEventHealthChecker());
 *
 *  Schedulable can't call out, so it starts the batch. The batch execute()
 *  (Database.AllowsCallouts) performs the Limits API call via healthCheckRunner.
 */
public with sharing class healthCheckPlatformEventHealthChecker
        implements Schedulable,
                   Database.Batchable<String>,
                   Database.AllowsCallouts,
                   Database.Stateful {

    private Id masterId;
    private static final String CHECKER_KEY = 'PLATFORM_EVENT';

    public healthCheckPlatformEventHealthChecker() {}

    public healthCheckPlatformEventHealthChecker(Id masterId) {
        this.masterId = masterId;
    }

    // ─────────────────────────────────────────────────────────────
    // SCHEDULER
    // ─────────────────────────────────────────────────────────────
    public void execute(SchedulableContext sc) {
        // Start batch with size 1 → ensures single execution + safe callout
        Database.executeBatch(
            new healthCheckPlatformEventHealthChecker(this.masterId),
            1
        );
    }

    // ─────────────────────────────────────────────────────────────
    // BATCH START
    // ─────────────────────────────────────────────────────────────
    public Iterable<String> start(Database.BatchableContext bc) {
        if (masterId == null) {
            masterId = healthCheckMasterJob.getOrCreateMaster().Id;
        }
        return new List<String>{ CHECKER_KEY };
    }

    // ─────────────────────────────────────────────────────────────
    // BATCH EXECUTE (MAIN LOGIC)
    // ─────────────────────────────────────────────────────────────
    public void execute(Database.BatchableContext bc, List<String> scope) {

        // Inline FIELD_LIST since it's private in runner
        String fieldList =
            'KPMG_Checker_Key__c, KPMG_Query_Type__c, KPMG_SObject_API_Name__c, ' +
            'KPMG_Select_Fields__c, KPMG_Where_Clause__c, KPMG_Order_By__c, KPMG_Row_Limit__c, ' +
            'KPMG_Is_Count_Query__c, KPMG_Section__c, KPMG_Sub_Section_Label__c, KPMG_Display_Order__c, ' +
            'KPMG_Amber_Threshold__c, KPMG_Red_Threshold__c, KPMG_Metric_Keys__c, ' +
            'KPMG_Label_Field__c, KPMG_Total_Field__c, KPMG_Used_Field__c, KPMG_Detail_Fields__c, ' +
            'KPMG_Empty_Message__c, KPMG_Apex_Handler__c';

        // Fetch ONLY platform event configs
        List<KPMG_Daily_Health_Check__c> configs = Database.query(
            'SELECT ' + fieldList +
            ' FROM KPMG_Daily_Health_Check__c' +
            ' WHERE KPMG_Active__c = true' +
            ' AND KPMG_Checker_Key__c = :CHECKER_KEY' +
            ' ORDER BY KPMG_Display_Order__c NULLS LAST'
        );

        if (configs.isEmpty()) return;

        // Build logs (includes Limits API callout if configured)
        List<KPMG_Health_Check_Log__c> logs =
            healthCheckRunner.buildLogs(configs, masterId);

        // Persist logs (all DML handled centrally)
        healthCheckRunner.persist(
            logs,
            healthCheckRunner.sectionsOf(configs),
            masterId
        );
    }

    // ─────────────────────────────────────────────────────────────
    // BATCH FINISH
    // ─────────────────────────────────────────────────────────────
    public void finish(Database.BatchableContext bc) {
        // No post-processing needed
    }
}