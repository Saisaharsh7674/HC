/**
 * @description  Central dynamic-SOQL engine for the Health Check framework.
 *
 *  All query definitions live in KPMG_Daily_Health_Check__c
 *
 *  SECURITY NOTE
 *  -------------
 *  Query fragments come only from Custom Metadata, which only admins with
 *  "Customize Application" can change. There is no end-user injection surface.
 *  Classes run "with sharing".
 */
public with sharing class healthCheckQueryService {

    public class QueryConfigException extends Exception {}

    // The full field set every consumer needs. Kept in one place.
    private static final String FIELD_LIST =
        'KPMG_Checker_Key__c, KPMG_Query_Type__c, KPMG_SObject_API_Name__c, ' +
        'KPMG_Select_Fields__c, KPMG_Where_Clause__c, KPMG_Order_By__c, KPMG_Row_Limit__c, ' +
        'KPMG_Is_Count_Query__c, KPMG_Section__c, KPMG_Sub_Section_Label__c, KPMG_Display_Order__c, ' +
        'KPMG_Amber_Threshold__c, KPMG_Red_Threshold__c, KPMG_Metric_Keys__c, ' +
        'KPMG_Label_Field__c, KPMG_Total_Field__c, KPMG_Used_Field__c, KPMG_Detail_Fields__c, ' +
        'KPMG_Empty_Message__c, KPMG_Apex_Handler__c';

    /** Every ACTIVE config row, in display order. Used by the single runner. */
    public static List<KPMG_Daily_Health_Check__c> getAllActive() {
        String soql =
            'SELECT ' + FIELD_LIST +
            ' FROM KPMG_Daily_Health_Check__c' +
            ' WHERE KPMG_Active__c = true' +
            ' ORDER BY KPMG_Display_Order__c NULLS LAST';
        return Database.query(soql);
    }

    /** Active config rows for one checker key (still used by the hourly PE job). */
    public static List<KPMG_Daily_Health_Check__c> getConfigs(String checkerKey) {
        String soql =
            'SELECT ' + FIELD_LIST +
            ' FROM KPMG_Daily_Health_Check__c' +
            ' WHERE KPMG_Active__c = true AND KPMG_Checker_Key__c = :checkerKey' +
            ' ORDER BY KPMG_Display_Order__c NULLS LAST';
        return Database.query(soql);
    }

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

    /** Comma-separated metadata value -> clean List<String>. */
    public static List<String> splitCsv(String csv) {
        List<String> out = new List<String>();
        if (String.isBlank(csv)) return out;
        for (String part : csv.split(',')) {
            if (String.isNotBlank(part)) out.add(part.trim());
        }
        return out;
    }
}