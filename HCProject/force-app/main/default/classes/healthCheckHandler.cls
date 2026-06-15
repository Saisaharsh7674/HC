/**
 * @description  Plug-in contract for checks that CANNOT be expressed as a
 *               metadata SOQL string (e.g. external API calls like Cvent/Trust,
 *               or bespoke Apex-error analysis).
 *
 *  A metadata row with KPMG_Query_Type__c = 'APEX_HANDLER' names the implementing
 *  class in KPMG_Apex_Handler__c. The single HealthCheckRunner instantiates it via
 *  Type.forName and calls run(). The handler MUST be side-effect-free: it
 *  returns log records only and performs NO DML (the runner owns all DML so
 *  the callout-before-DML ordering stays intact).
 */
public interface healthCheckHandler {
    List<KPMG_Health_Check_Log__c> run(KPMG_Daily_Health_Check__c cfg, Id masterId);
}