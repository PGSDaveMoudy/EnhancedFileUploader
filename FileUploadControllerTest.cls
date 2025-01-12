@IsTest
public class FileUploadControllerTest {

    @TestSetup
    static void setup() {
        // Create a dummy record to link files to
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        // Add test data for ContentVersion
        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = '/TestFile.pdf',
            VersionData = Blob.valueOf('Sample file content'),
            IsMajorVersion = true
        );
        insert cv;
    }

    @IsTest
    static void testUploadFile() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        String fileName = 'testFile.pdf';
        String base64Data = EncodingUtil.base64Encode(Blob.valueOf('Test file content'));

        Test.startTest();
        Id contentDocumentId = FileUploadController.uploadFile(fileName, base64Data, account.Id);
        Test.stopTest();

        System.assertNotEquals(null, contentDocumentId, 'ContentDocumentId should not be null');

        ContentDocumentLink link = [
            SELECT Id, LinkedEntityId 
            FROM ContentDocumentLink 
            WHERE ContentDocumentId = :contentDocumentId
            LIMIT 1
        ];
        System.assertEquals(account.Id, link.LinkedEntityId, 'The file should be linked to the provided record.');
    }

        @IsTest
    static void testCreatePublicLink() {
        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion LIMIT 1].ContentDocumentId;

        Test.startTest();
        FileUploadController.DistributionWrapper wrapper = FileUploadController.createPublicLink(contentDocumentId);
        Test.stopTest();

        System.assertNotEquals(null, wrapper.distributionId, 'DistributionId should not be null');
        System.assertNotEquals(null, wrapper.distributionPublicUrl, 'DistributionPublicUrl should not be null');
    }

    @IsTest
    static void testGetLatestContentVersionId() {
        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion LIMIT 1].ContentDocumentId;

        Test.startTest();
        String latestContentVersionId = FileUploadController.getLatestContentVersionId(contentDocumentId);
        Test.stopTest();

        System.assertNotEquals(null, latestContentVersionId, 'Latest ContentVersionId should not be null');
    }

    @IsTest
    static void testDeleteFile() {
        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion LIMIT 1].ContentDocumentId;
        FileUploadController.DistributionWrapper wrapper = FileUploadController.createPublicLink(contentDocumentId);

        Test.startTest();
        FileUploadController.deleteFile(contentDocumentId, null, wrapper.distributionId);
        Test.stopTest();

        List<ContentDistribution> distributions = [
            SELECT Id FROM ContentDistribution WHERE Id = :wrapper.distributionId
        ];
        System.assertEquals(0, distributions.size(), 'Public link should be deleted');

        List<ContentDocument> documents = [
            SELECT Id FROM ContentDocument WHERE Id = :contentDocumentId
        ];
        System.assertEquals(0, documents.size(), 'ContentDocument should be deleted');
    }
}
