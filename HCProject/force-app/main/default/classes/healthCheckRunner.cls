/**
 * @description  THE single automated health-check engine.
 *
 *  This one class owns the entire automated pipeline:
 *    - dynamic SOQL building / querying (formerly HealthCheckQueryService)
 *    - the Apex plug-in contract (formerly the HealthCheckHandler interface,
 *      now the nested `Handler` interface below)
 *    - per-strategy evaluation into log records (NO DML)
 *    - persistence of those records (ALL DML)
 *
 *  HealthCheck_MasterJob enqueues ONLY this class. Everything it does is driven
 *  by the active KPMG_Daily_Health_Check__c rows — add, remove or retune a check
 *  by editing metadata in Setup, no release required.
 *
 *  Each metadata row declares a strategy in KPMG_Query_Type__c:
 *    USAGE        - query rows; per row RAG on Used/Total fields
 *                   (KPMG_Label_Field__c, KPMG_Total_Field__c, KPMG_Used_Field__c)
 *    COUNT        - SELECT COUNT(); RAG by count vs Amber/Red thresholds
 *    FAILURES     - query "bad" rows -> one RED log each; green Empty_Message if none
 *                   (KPMG_Label_Field__c for sub-section, KPMG_Detail_Fields__c for details)
 *    LIMITS_API   - callout to the /limits/ REST path in KPMG_Where_Clause__c;
 *                   per metric in KPMG_Metric_Keys__c, RAG on Used/Max
 *    APEX_HANDLER - delegates to the class named in KPMG_Apex_Handler__c
 *                   (implements healthCheckRunner.Handler) for non-SOQL checks
 *
 *  ORDERING: buildLogs() does ONLY queries + callouts (no DML). All DML happens
 *  afterwards in persist(). That is what keeps callouts legal in this one
 *  transaction (you cannot call out after uncommitted DML).
 *
 *  SECURITY: query fragments come only from Custom Metadata, editable solely by
 *  admins with "Customize Application" — there is no end-user injection surface.
 *  Runs "with sharing".
 */
public with sharing class healthCheckRunner
        implements Queueable, Database.AllowsCallouts {
 
    /**
     * @description Plug-in contract for checks that CANNOT be expressed as a
     *              metadata SOQL string (e.g. external API calls, or bespoke
     *              Apex-error analysis). A metadata row with
     *              KPMG_Query_Type__c = 'APEX_HANDLER' names the implementing
     *              class in KPMG_Apex_Handler__c; the runner instantiates it via
     *              Type.forName and calls run(). Implementations MUST be
     *              side-effect-free: return log records only, perform NO DML
     *              (the runner owns all DML so callout-before-DML ordering holds).
     */
    public interface Handler {
        List<KPMG_Health_Check_Log__c> run(KPMG_Daily_Health_Check__c cfg, Id masterId);
    }
 
    public class QueryConfigException extends Exception {}
 
    // The full config field set every consumer needs. Kept in one place.
    private static final String FIELD_LIST =
        'KPMG_Checker_Key__c, KPMG_Query_Type__c, KPMG_SObject_API_Name__c, ' +
        'KPMG_Select_Fields__c, KPMG_Where_Clause__c, KPMG_Order_By__c, KPMG_Row_Limit__c, ' +
        'KPMG_Is_Count_Query__c, KPMG_Section__c, KPMG_Sub_Section_Label__c, KPMG_Display_Order__c, ' +
        'KPMG_Amber_Threshold__c, KPMG_Red_Threshold__c, KPMG_Metric_Keys__c, ' +
        'KPMG_Label_Field__c, KPMG_Total_Field__c, KPMG_Used_Field__c, KPMG_Detail_Fields__c, ' +
        'KPMG_Empty_Message__c, KPMG_Apex_Handler__c';
 
    private Id masterId;
 
    public healthCheckRunner(Id masterId) {
        this.masterId = masterId;
    }
 
    public void execute(QueueableContext ctx) {
        if (masterId == null) {
            masterId = healthCheckMasterJob.getOrCreateMaster().Id;
        }
        List<KPMG_Daily_Health_Check__c> configs = getAllActive();
        List<KPMG_Health_Check_Log__c> logs = buildLogs(configs, masterId);  // queries + callouts only
        persist(logs, sectionsOf(configs), masterId);                        // all DML here
    }
 
    // ── Config retrieval ──────────────────────────────────────────────────────
 
    /** Every ACTIVE config row, in display order. */
    public static List<KPMG_Daily_Health_Check__c> getAllActive() {
        String soql =
            'SELECT ' + FIELD_LIST +
            ' FROM KPMG_Daily_Health_Check__c' +
            ' WHERE KPMG_Active__c = true' +
            ' ORDER BY KPMG_Display_Order__c NULLS LAST';
        return Database.query(soql);
    }
 
    // ── Reusable evaluation ─────────────────────────────────────────────────
 
    /** Evaluates configs into log records. Performs NO DML. */
    public static List<KPMG_Health_Check_Log__c> buildLogs(
            List<KPMG_Daily_Health_Check__c> configs, Id masterId) {
 
        List<KPMG_Health_Check_Log__c> logs = new List<KPMG_Health_Check_Log__c>();
        for (KPMG_Daily_Health_Check__c cfg : configs) {
            String strategy = String.isBlank(cfg.KPMG_Query_Type__c)
                ? 'USAGE' : cfg.KPMG_Query_Type__c.toUpperCase();
 
            if (strategy == 'LIMITS_API') {
                logs.addAll(handleLimitsApi(cfg, masterId));
            } else if (isCount(cfg) || strategy == 'COUNT') {
                logs.add(handleCount(cfg, masterId));
            } else if (strategy == 'FAILURES') {
                logs.addAll(handleFailures(cfg, masterId));
            } else if (strategy == 'APEX_HANDLER') {
                logs.addAll(handleApex(cfg, masterId));
            } else { // USAGE (default)
                logs.addAll(handleUsage(cfg, masterId));
            }
        }
        return logs;
    }
 
    /** Deletes prior automated logs for the touched sections, then inserts. */
    public static void persist(List<KPMG_Health_Check_Log__c> logs,
                               Set<String> sections, Id masterId) {
        if (!sections.isEmpty()) {
            delete [
                SELECT Id FROM KPMG_Health_Check_Log__c
                WHERE KPMG_Daily_Health_Check__c = :masterId
                AND   KPMG_Is_Manual__c = false
                AND   KPMG_Section__c IN :sections
            ];
        }
        if (!logs.isEmpty()) insert logs;
    }
 
    public static Set<String> sectionsOf(List<KPMG_Daily_Health_Check__c> configs) {
        Set<String> s = new Set<String>();
        for (KPMG_Daily_Health_Check__c cfg : configs) {
            if (String.isNotBlank(cfg.KPMG_Section__c)) s.add(cfg.KPMG_Section__c);
        }
        return s;
    }
 
    // ── Strategy handlers ─────────────────────────────────────────────────────
 
    private static List<KPMG_Health_Check_Log__c> handleUsage(
            KPMG_Daily_Health_Check__c cfg, Id masterId) {
        Integer amber = intOr(cfg.KPMG_Amber_Threshold__c, 85);
        Integer red   = intOr(cfg.KPMG_Red_Threshold__c, 95);
        String labelF = strOr(cfg.KPMG_Label_Field__c, 'MasterLabel');
        String totalF = strOr(cfg.KPMG_Total_Field__c, 'TotalLicenses');
        String usedF  = strOr(cfg.KPMG_Used_Field__c, 'UsedLicenses');
 
        List<KPMG_Health_Check_Log__c> out = new List<KPMG_Health_Check_Log__c>();
        for (SObject row : runQuery(cfg)) {
            String  label = String.valueOf(getFieldValue(row, labelF));
            Decimal total = toDecimal(getFieldValue(row, totalF));
            Decimal used  = toDecimal(getFieldValue(row, usedF));
            Decimal rem   = total - used;
            out.add(log(cfg, masterId, label,
                HealthCheck_Constants.ragStatus(used, total, amber, red),
                total, used,
                'Total: ' + total + ' | Used: ' + used + ' | Remaining: ' + rem));
        }
        return out;
    }
 
    private static KPMG_Health_Check_Log__c handleCount(
            KPMG_Daily_Health_Check__c cfg, Id masterId) {
        Integer cnt   = runCount(cfg);
        Integer amber = cfg.KPMG_Amber_Threshold__c != null ? cfg.KPMG_Amber_Threshold__c.intValue() : 1;
        Integer red   = cfg.KPMG_Red_Threshold__c   != null ? cfg.KPMG_Red_Threshold__c.intValue()   : null;
 
        String status = HealthCheck_Constants.STATUS_GREEN;
        if (red != null && cnt >= red)      status = HealthCheck_Constants.STATUS_RED;
        else if (cnt >= amber)              status = HealthCheck_Constants.STATUS_AMBER;
 
        String sub = strOr(cfg.KPMG_Sub_Section_Label__c, 'Count');
        return log(cfg, masterId, sub, status, null, null, sub + ': ' + cnt);
    }
 
    private static List<KPMG_Health_Check_Log__c> handleFailures(
            KPMG_Daily_Health_Check__c cfg, Id masterId) {
        List<SObject> rows = runQuery(cfg);
        List<KPMG_Health_Check_Log__c> out = new List<KPMG_Health_Check_Log__c>();
 
        if (rows.isEmpty()) {
            out.add(log(cfg, masterId,
                strOr(cfg.KPMG_Sub_Section_Label__c, 'All Jobs'),
                HealthCheck_Constants.STATUS_GREEN, null, null,
                strOr(cfg.KPMG_Empty_Message__c, 'No issues found.')));
            return out;
        }
 
        String labelF = strOr(cfg.KPMG_Label_Field__c, 'Name');
        List<String> detailFs = splitCsv(cfg.KPMG_Detail_Fields__c);
 
        for (SObject row : rows) {
            Object lbl = getFieldValue(row, labelF);
            String sub = lbl == null ? 'Unknown' : String.valueOf(lbl);
 
            List<String> parts = new List<String>();
            for (String f : detailFs) {
                Object v = getFieldValue(row, f);
                if (v != null) {
                    String fLabel = f.contains('.') ? f.substringAfterLast('.') : f;
                    parts.add(fLabel + ': ' + v);
                }
            }
            out.add(log(cfg, masterId, sub, HealthCheck_Constants.STATUS_RED,
                null, null, String.join(parts, ' | ')));
        }
        return out;
    }
 
    private static List<KPMG_Health_Check_Log__c> handleApex(
            KPMG_Daily_Health_Check__c cfg, Id masterId) {
        if (String.isBlank(cfg.KPMG_Apex_Handler__c)) return new List<KPMG_Health_Check_Log__c>();
        Type t = Type.forName(cfg.KPMG_Apex_Handler__c.trim());
        if (t == null) {
            return new List<KPMG_Health_Check_Log__c>{
                log(cfg, masterId, cfg.KPMG_Apex_Handler__c,
                    HealthCheck_Constants.STATUS_RED, null, null,
                    'Handler class not found: ' + cfg.KPMG_Apex_Handler__c)
            };
        }
        Handler h = (Handler) t.newInstance();
        return h.run(cfg, masterId);
    }
 
    private static List<KPMG_Health_Check_Log__c> handleLimitsApi(
            KPMG_Daily_Health_Check__c cfg, Id masterId) {
        List<KPMG_Health_Check_Log__c> out = new List<KPMG_Health_Check_Log__c>();
        Integer amber = intOr(cfg.KPMG_Amber_Threshold__c, 50);
        Integer red   = intOr(cfg.KPMG_Red_Threshold__c, 80);
 
        Map<String, Object> limitsMap;
        try {
            limitsMap = fetchLimits(cfg);
        } catch (Exception ex) {
            out.add(log(cfg, masterId, 'Limits API Call',
                HealthCheck_Constants.STATUS_RED, null, null,
                'Callout failed: ' + ex.getMessage()));
            return out;
        }
        if (limitsMap == null) return out;
 
        for (String evType : splitCsv(cfg.KPMG_Metric_Keys__c)) {
            Map<String, Object> metric = (Map<String, Object>) limitsMap.get(evType);
            if (metric == null) continue;
 
            Long maxVal    = getLong(metric, 'Max');
            Long remaining = getLong(metric, 'Remaining');
            Long used      = maxVal - remaining;
            Decimal pct    = maxVal > 0 ? ((Decimal) used / maxVal * 100).setScale(2) : 0;
 
            out.add(log(cfg, masterId, evType,
                HealthCheck_Constants.ragStatus(used, maxVal, amber, red),
                maxVal, used,
                'Max: ' + maxVal + ' | Remaining: ' + remaining +
                ' | Used: ' + used + ' | ' + pct + '% consumed'));
        }
        return out;
    }
 
    private static Map<String, Object> fetchLimits(KPMG_Daily_Health_Check__c cfg) {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        String path = String.isNotBlank(cfg.KPMG_Where_Clause__c)
            ? cfg.KPMG_Where_Clause__c.trim() : '/services/data/v62.0/limits/';
 
        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseUrl + path);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setTimeout(10000);
 
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() == 200) {
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        }
        throw new QueryConfigException('Limits API returned HTTP ' + res.getStatusCode());
    }
 
    // ── Dynamic SOQL engine ─────────────────────────────────────────────────
 
    /** True if this config should run as SELECT COUNT(). */
    public static Boolean isCount(KPMG_Daily_Health_Check__c cfg) {
        return cfg.KPMG_Is_Count_Query__c == true
            || 'COUNT'.equalsIgnoreCase(cfg.KPMG_Query_Type__c);
    }
 
    /** Assembles a SOQL string from a config row. Blank clauses are skipped. */
    public static String buildSoql(KPMG_Daily_Health_Check__c cfg) {
        if (cfg == null || String.isBlank(cfg.KPMG_SObject_API_Name__c)) {
            throw new QueryConfigException(
                'KPMG_SObject_API_Name__c is required on config ' +
                (cfg == null ? '(null)' : cfg.KPMG_Section__c));
        }
        Boolean countQ = isCount(cfg);
 
        String fields = countQ
            ? 'COUNT()'
            : (String.isBlank(cfg.KPMG_Select_Fields__c) ? 'Id' : cfg.KPMG_Select_Fields__c.trim());
 
        String soql = 'SELECT ' + fields + ' FROM ' + cfg.KPMG_SObject_API_Name__c.trim();
 
        if (String.isNotBlank(cfg.KPMG_Where_Clause__c)) {
            soql += ' WHERE ' + cfg.KPMG_Where_Clause__c.trim();
        }
        if (!countQ && String.isNotBlank(cfg.KPMG_Order_By__c)) {
            soql += ' ORDER BY ' + cfg.KPMG_Order_By__c.trim();
        }
        if (!countQ && cfg.KPMG_Row_Limit__c != null) {
            soql += ' LIMIT ' + String.valueOf(cfg.KPMG_Row_Limit__c.intValue());
        }
        return soql;
    }
 
    public static List<SObject> runQuery(KPMG_Daily_Health_Check__c cfg) {
        return Database.query(buildSoql(cfg));
    }
 
    public static Integer runCount(KPMG_Daily_Health_Check__c cfg) {
        return Database.countQuery(buildSoql(cfg));
    }
 
    // ── Generic helpers ────────────────────────────────────────────────────────
 
    private static KPMG_Health_Check_Log__c log(KPMG_Daily_Health_Check__c cfg, Id masterId,
            String sub, String status, Decimal total, Decimal used, String details) {
        return new KPMG_Health_Check_Log__c(
            KPMG_Daily_Health_Check__c = masterId,
            KPMG_Section__c            = cfg.KPMG_Section__c,
            KPMG_Sub_Section__c        = sub,
            KPMG_Status__c             = status,
            KPMG_Total__c              = total,
            KPMG_Used__c               = used,
            KPMG_Details__c            = details,
            KPMG_Is_Manual__c          = false,
            KPMG_Is_Pending__c         = false,
            KPMG_Display_Order__c      = cfg.KPMG_Display_Order__c != null
                                        ? cfg.KPMG_Display_Order__c.intValue() : 0,
            KPMG_Run_By__c             = 'Automated'
        );
    }
 
    /** Comma-separated metadata value -> clean List<String>. */
    public static List<String> splitCsv(String csv) {
        List<String> out = new List<String>();
        if (String.isBlank(csv)) return out;
        for (String part : csv.split(',')) {
            if (String.isNotBlank(part)) out.add(part.trim());
        }
        return out;
    }
 
    /** Traverses dotted relationship paths e.g. 'ApexClass.Name'. */
    private static Object getFieldValue(SObject row, String path) {
        if (row == null || String.isBlank(path)) return null;
        List<String> parts = path.trim().split('\\.');
        SObject cur = row;
        for (Integer i = 0; i < parts.size() - 1; i++) {
            if (cur == null) return null;
            cur = cur.getSObject(parts[i]);
        }
        return cur == null ? null : cur.get(parts[parts.size() - 1]);
    }
 
    private static Decimal toDecimal(Object v) {
        if (v == null) return 0;
        if (v instanceof Decimal) return (Decimal) v;
        if (v instanceof Integer) return (Decimal) (Integer) v;
        if (v instanceof Long)    return (Decimal) (Long) v;
        return Decimal.valueOf(String.valueOf(v));
    }
 
    private static Long getLong(Map<String, Object> m, String key) {
        Object v = m.get(key);
        if (v instanceof Long)    return (Long) v;
        if (v instanceof Integer) return (Long) (Integer) v;
        if (v instanceof Decimal) return ((Decimal) v).longValue();
        return 0L;
    }
 
    private static Integer intOr(Decimal d, Integer fallback) {
        return d != null ? d.intValue() : fallback;
    }
    private static String strOr(String s, String fallback) {
        return String.isNotBlank(s) ? s.trim() : fallback;
    }
}