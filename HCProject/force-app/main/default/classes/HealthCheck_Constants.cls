/**
 * @description Shared constants for the Daily Health Check automation.
 *              Centralises section names, display ordering, and manual section definitions.
 */
public with sharing class HealthCheck_Constants {

    // ─── Section names ───────────────────────────────────────────────────────
    public static final String SEC_INTEGRATIONS   = 'Sales Cloud Integrations';
    public static final String SEC_PROCESS        = 'Process';
    public static final String SEC_MONITORING     = 'Sources/Items';
    public static final String SEC_ERROR_LOGS     = 'System Error Logs';
    public static final String SEC_PLATFORM_EVT   = 'Platform Events';
    public static final String SEC_USER_LIC       = 'User Licenses';
    public static final String SEC_PSL            = 'Permission Set Licenses';
    public static final String SEC_SCHED_JOBS     = 'Scheduled Jobs';
    public static final String SEC_AUP            = 'AUP Provisioning';
    public static final String SEC_SC_HEALTH      = 'SC Health Check';
    public static final String SEC_OM_DASHBOARD   = 'OM Dashboard';
    public static final String SEC_WORKBENCH      = 'WorkBench';
    public static final String SEC_TRUST          = 'Salesforce Trust';
    public static final String SEC_SERVICE_ACCTS  = 'Service Accounts';
    public static final String SEC_MULESOFT       = 'MuleSoft Integration Errors';
    public static final String SEC_CVENT          = 'Cvent Errors';

    // ─── Status values ────────────────────────────────────────────────────────
    public static final String STATUS_GREEN   = 'Green';
    public static final String STATUS_AMBER   = 'Amber';
    public static final String STATUS_RED     = 'Red';
    public static final String STATUS_NA      = 'N/A';
    public static final String STATUS_PENDING = 'Pending';

    // ─── Manual section placeholders (Section__c → Sub_Section__c → Display Order) ──
    public static final List<ManualSectionDef> MANUAL_SECTIONS = new List<ManualSectionDef>{
        new ManualSectionDef(SEC_INTEGRATIONS,  'Introhive',          1,  1),
        new ManualSectionDef(SEC_INTEGRATIONS,  'BoardEx',            2,  2),
        new ManualSectionDef(SEC_INTEGRATIONS,  'Cvent Connection',   3,  3),
        new ManualSectionDef(SEC_INTEGRATIONS,  'MuleSoft',           4,  4),
        new ManualSectionDef(SEC_INTEGRATIONS,  'Marketing Cloud',    5,  5),
        new ManualSectionDef(SEC_INTEGRATIONS,  'TrailTracker',       6,  6),
        new ManualSectionDef(SEC_INTEGRATIONS,  'Outlook Plugin',     7,  7),
        new ManualSectionDef(SEC_PROCESS,       'Sales Cloud Login',  8,  8),
        new ManualSectionDef(SEC_PROCESS,       'Flows',              9,  9),
        new ManualSectionDef(SEC_PROCESS,       'Proactive Monitoring Alerts', 10,  10),
        new ManualSectionDef(SEC_MONITORING,    'SolarWind / P1s / P2s', 11, 11),
        new ManualSectionDef(SEC_SC_HEALTH,     'SC Health Check Score', 12, 12),
        new ManualSectionDef(SEC_OM_DASHBOARD,  'Daily Field Tracker (High Priority)', 13, 13),
        new ManualSectionDef(SEC_OM_DASHBOARD,  'Daily Field Tracker (Low Priority)',  14, 14),
        new ManualSectionDef(SEC_WORKBENCH,     'WorkBench Observations', 15, 15),
        new ManualSectionDef(SEC_MULESOFT,      'MuleSoft Daily Digest',  16, 16),
        new ManualSectionDef(SEC_SERVICE_ACCTS, 'Salesforce Trust', 17, 17)
    };

    // ─── Automated section display orders ────────────────────────────────────
    public static final Integer ORD_USER_LIC     = 20;
    public static final Integer ORD_PSL          = 21;
    public static final Integer ORD_PLATFORM_EVT = 22;
    public static final Integer ORD_SCHED_JOBS   = 23;
    public static final Integer ORD_ERROR_LOGS   = 24;
    public static final Integer ORD_CVENT        = 25;
    public static final Integer ORD_AUP          = 26;
    public static final Integer ORD_TRUST        = 27;

    // ─── Helper inner class ───────────────────────────────────────────────────
    public class ManualSectionDef {
        public String section;
        public String subSection;
        public Integer displayOrder;
        public Integer emailOrder;

        public ManualSectionDef(String sec, String sub, Integer dispOrd, Integer emailOrd) {
            this.section      = sec;
            this.subSection   = sub;
            this.displayOrder = dispOrd;
            this.emailOrder   = emailOrd;
        }
    }

    // ─── RAG evaluation ──────────────────────────────────────────────────────
    public static String ragStatus(Decimal used, Decimal total,
                                   Decimal amberPct, Decimal redPct) {
        if (total == null || total == 0) return STATUS_NA;
        Decimal pct = (used / total) * 100;
        if (pct >= redPct)   return STATUS_RED;
        if (pct >= amberPct) return STATUS_AMBER;
        return STATUS_GREEN;
    }
}