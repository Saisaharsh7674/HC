@IsTest
private class healthCheckPlatformEventTest {

    /**
     * Creates minimal config data required for PLATFORM_EVENT execution.
     */
    private static void createTestConfig() {
        insert new KPMG_Daily_Health_Check__c(
            KPMG_Active__c = true,
            KPMG_Checker_Key__c = 'PLATFORM_EVENT',
            KPMG_Query_Type__c = 'LIMITS_API',
            KPMG_Section__c = 'Platform Events',
            KPMG_Sub_Section_Label__c = 'Daily Usage',
            KPMG_Display_Order__c = 1,
            KPMG_Metric_Keys__c = 'DailyPlatformEvents',
            KPMG_Amber_Threshold__c = 50,
            KPMG_Red_Threshold__c = 80
        );
    }

    /**
     * Mock for Limits API callout
     */
    private class LimitsApiMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            // Fake Limits API response
            res.setBody(JSON.serialize(new Map<String, Object>{
                'DailyPlatformEvents' => new Map<String, Object>{
                    'Max' => 1000,
                    'Remaining' => 400
                }
            }));
            return res;
        }
    }

    @IsTest
    static void testBatchExecution() {
        // Setup data
        createTestConfig();

        // Register mock callout
        Test.setMock(HttpCalloutMock.class, new LimitsApiMock());

        Test.startTest();

        // Run batch
        Database.executeBatch(
            new healthCheckPlatformEventHealthChecker(),
            1
        );

        Test.stopTest();

        // Verify logs inserted
        List<KPMG_Health_Check_Log__c> logs = [
            SELECT Id, KPMG_Status__c, KPMG_Sub_Section__c
            FROM KPMG_Health_Check_Log__c
        ];

        System.assert(!logs.isEmpty(), 'Logs should be created');
        System.assertEquals('DailyPlatformEvents', logs[0].KPMG_Sub_Section__c);
    }

    @IsTest
    static void testSchedulableExecution() {
        // Setup data
        createTestConfig();

        // Register mock
        Test.setMock(HttpCalloutMock.class, new LimitsApiMock());

        Test.startTest();

        // Schedule job
        String jobId = System.schedule(
            'Test PE Health Check',
            '0 0 0 1 1 ? 2050',
            new healthCheckPlatformEventHealthChecker()
        );

        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job should be scheduled');
    }

    @IsTest
    static void testWithCustomMasterId() {
        createTestConfig();
        Test.setMock(HttpCalloutMock.class, new LimitsApiMock());

        // Create fake master record
        KPMG_Daily_Health_Check__c master =
            healthCheckMasterJob.getOrCreateMaster();

        Test.startTest();

        Database.executeBatch(
            new healthCheckPlatformEventHealthChecker(master.Id),
            1
        );

        Test.stopTest();

        List<KPMG_Health_Check_Log__c> logs = [
            SELECT Id
            FROM KPMG_Health_Check_Log__c
            WHERE KPMG_Daily_Health_Check__c = :master.Id
        ];

        System.assert(!logs.isEmpty(), 'Logs should be tied to master record');
    }
}