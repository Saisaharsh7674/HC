/**
 * @description Schedulable entry point for the Sales Cloud Daily Health Check.
 *              Runs at 06:00 AM daily.
 *
 *  Schedule via Anonymous Apex:
 *    System.schedule('HC Daily Master', '0 0 6 * * ?', new HealthCheck_MasterJob());
 *
 *  CHANGES vs original:
 *   - getOrCreateMaster() is now PUBLIC STATIC (re-used by PlatformEventHealthChecker
 *     and HealthCheckLauncher).
 *   - run() now RETURNS the master Id so the LWC launcher can report it.
 */
public with sharing class healthCheckMasterJob implements Schedulable {

    public void execute(SchedulableContext ctx) {
        run();
    }

    /**
     * @description Creates (or reuses) today's KPMG_Daily_Health_Check__c master record,
     *              seeds manual placeholder log entries, and kicks off all automated checkers.
     * @return Id of today's master record.
     */
    public static Id run() {
        KPMG_Daily_Health_Check__c master = getOrCreateMaster();

        seedManualPlaceholders(master.Id);

        // Single metadata-driven engine handles every automated check.
        // Add / remove checks by editing KPMG_Health_Check_Query__mdt — no release.
        System.enqueueJob(new HealthCheckRunner(master.Id));

        return master.Id;
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    public static KPMG_Daily_Health_Check__c getOrCreateMaster() {
        List<KPMG_Daily_Health_Check__c> existing = [
            SELECT Id, KPMG_Check_Date__c, KPMG_Email_Sent__c
            FROM KPMG_Daily_Health_Check__c
            WHERE KPMG_Check_Date__c = TODAY
            LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        KPMG_Daily_Health_Check__c master = new KPMG_Daily_Health_Check__c(
            KPMG_Check_Date__c = Date.today()
        );
                
        insert master;
        return master;
    }

    private static void seedManualPlaceholders(Id masterId) {
        Set<String> existingKeys = new Set<String>();
        for (KPMG_Health_Check_Log__c log : [
            SELECT KPMG_Section__c, KPMG_Sub_Section__c
            FROM KPMG_Health_Check_Log__c
            WHERE KPMG_Daily_Health_Check__c = :masterId
            AND   KPMG_Is_Manual__c = true
        ]) {
            existingKeys.add(log.KPMG_Section__c + '|' + log.KPMG_Sub_Section__c);
        }

        List<KPMG_Health_Check_Log__c> toInsert = new List<KPMG_Health_Check_Log__c>();
        for (HealthCheck_Constants.ManualSectionDef def : HealthCheck_Constants.MANUAL_SECTIONS) {
            String key = def.section + '|' + def.subSection;
            if (!existingKeys.contains(key)) {
                toInsert.add(new KPMG_Health_Check_Log__c(
                    KPMG_Daily_Health_Check__c = masterId,
                    KPMG_Section__c            = def.section,
                    KPMG_Sub_Section__c        = def.subSection,
                    KPMG_Status__c             = HealthCheck_Constants.STATUS_PENDING,
                    KPMG_Is_Manual__c          = true,
                    KPMG_Is_Pending__c         = true,
                    KPMG_Display_Order__c      = def.displayOrder,
                    KPMG_Run_By__c             = 'Manual'
                ));
            }
        }
        if (!toInsert.isEmpty()) insert toInsert;
    }
}