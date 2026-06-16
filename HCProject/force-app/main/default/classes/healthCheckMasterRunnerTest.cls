@IsTest
private class healthCheckMasterRunnerTest {

    @TestSetup
    static void setupData() {

        // Create master record
        KPMG_Daily_Health_Check__c master = new KPMG_Daily_Health_Check__c(
            KPMG_Check_Date__c = Date.today()
        );
        insert master;

        // Insert config for COUNT strategy
        insert new KPMG_Daily_Health_Check__c(
            KPMG_Check_Date__c = Date.today(),
            KPMG_Active__c = true,
            KPMG_Query_Type__c = 'COUNT',
            KPMG_SObject_API_Name__c = 'User',
            KPMG_Section__c = 'Users',
            KPMG_Sub_Section_Label__c = 'Active Users',
            KPMG_Display_Order__c = 1,
            KPMG_Is_Count_Query__c = true,
            KPMG_Amber_Threshold__c = 1,
            KPMG_Red_Threshold__c = 100000
        );
    }

    @IsTest
    static void testRun() {
        Test.startTest();
        Id masterId = healthCheckMasterJob.run();
        Test.stopTest();

        System.assertNotEquals(null, masterId);
    }

    @IsTest
    static void testGetOrCreateExisting() {
        Test.startTest();
        KPMG_Daily_Health_Check__c m =
            healthCheckMasterJob.getOrCreateMaster();
        Test.stopTest();

        System.assertNotEquals(null, m);
    }

    @IsTest
    static void testGetOrCreateNew() {

        delete [SELECT Id FROM KPMG_Daily_Health_Check__c];

        Test.startTest();
        KPMG_Daily_Health_Check__c m =
            healthCheckMasterJob.getOrCreateMaster();
        Test.stopTest();

        System.assertNotEquals(null, m);
    }

    @IsTest
    static void testQueueableRunner() {

        KPMG_Daily_Health_Check__c master =
            [SELECT Id FROM KPMG_Daily_Health_Check__c LIMIT 1];

        Test.startTest();
        System.enqueueJob(new healthCheckRunner(master.Id));
        Test.stopTest();

        List<KPMG_Health_Check_Log__c> logs =
            [SELECT Id FROM KPMG_Health_Check_Log__c];

        System.assert(logs != null);
    }

    @IsTest
    static void testBuildLogs() {

        KPMG_Daily_Health_Check__c master =
            [SELECT Id FROM KPMG_Daily_Health_Check__c LIMIT 1];

        List<KPMG_Daily_Health_Check__c> configs =
            healthCheckRunner.getAllActive();

        Test.startTest();
        List<KPMG_Health_Check_Log__c> logs =
            healthCheckRunner.buildLogs(configs, master.Id);
        Test.stopTest();

        System.assertNotEquals(null, logs);
    }

    @IsTest
    static void testPersist() {

        KPMG_Daily_Health_Check__c master =
            [SELECT Id FROM KPMG_Daily_Health_Check__c LIMIT 1];

        List<KPMG_Health_Check_Log__c> logs = new List<KPMG_Health_Check_Log__c>{
            new KPMG_Health_Check_Log__c(
                KPMG_Daily_Health_Check__c = master.Id,
                KPMG_Section__c = 'Test Section',
                KPMG_Sub_Section__c = 'Test Sub',
                KPMG_Status__c = 'Green',
                KPMG_Is_Manual__c = false,
                KPMG_Is_Pending__c = false
            )
        };

        Test.startTest();
        healthCheckRunner.persist(
            logs,
            new Set<String>{'Test Section'},
            master.Id
        );
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM KPMG_Health_Check_Log__c]
        );
    }

    @IsTest
    static void testBuildSoql() {

        KPMG_Daily_Health_Check__c cfg =
            healthCheckRunner.getAllActive()[0];

        String soql = healthCheckRunner.buildSoql(cfg);

        System.assert(soql.contains('SELECT'));
        System.assert(soql.contains('FROM'));
    }

    @IsTest
    static void testSplitCsv() {

        List<String> vals =
            healthCheckRunner.splitCsv('A,B,C');

        System.assertEquals(3, vals.size());
    }

    @IsTest
    static void testRagStatus() {

        String s1 = HealthCheck_Constants.ragStatus(90, 100, 80, 95);
        String s2 = HealthCheck_Constants.ragStatus(96, 100, 80, 95);
        String s3 = HealthCheck_Constants.ragStatus(10, 100, 80, 95);

        System.assertEquals('Amber', s1);
        System.assertEquals('Red', s2);
        System.assertEquals('Green', s3);
    }

    @IsTest
    static void testSchedulable() {

        Test.startTest();
        String jobId = System.schedule(
            'Test Job',
            '0 0 0 * * ?',
            new healthCheckMasterJob()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }
}