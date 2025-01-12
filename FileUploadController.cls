public without sharing class FileUploadController {

    /**
     * Upload a file as a ContentVersion. 
     * If recordId is provided, link the resulting ContentDocument to that record.
     * Returns the newly created ContentDocumentId.
     */
    @AuraEnabled
    public static Id uploadFile(String fileName, String base64Data, Id recordId) {
        if (String.isBlank(fileName) || String.isBlank(base64Data)) {
            throw new AuraHandledException('File name and data are required.');
        }

        Blob fileBody;
        try {
            fileBody = EncodingUtil.base64Decode(base64Data);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid file data.');
        }

        // Enforce file size limit (e.g., 5MB for guest uploads)
        Integer fileSizeMB = fileBody.size() / (1024 * 1024);
        if (fileSizeMB > 5) { // Adjust as needed
            throw new AuraHandledException('File size exceeds the 5MB limit.');
        }

        // Enforce allowed file types
        String fileExtension = fileName.substringAfterLast('.').toLowerCase();
        Set<String> allowedExtensions = new Set<String>{'png', 'jpg', 'jpeg', 'gif', 'pdf'};
        if (!allowedExtensions.contains(fileExtension)) {
            throw new AuraHandledException('Unsupported file type. Allowed types: PNG, JPG, JPEG, GIF, PDF.');
        }

        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = '/' + fileName;
        cv.VersionData = fileBody;
        insert cv;

        Id contentDocumentId = [
            SELECT ContentDocumentId 
            FROM ContentVersion 
            WHERE Id = :cv.Id
            LIMIT 1
        ].ContentDocumentId;

        // If a recordId is provided, link the file to that record
        if (recordId != null) {
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.LinkedEntityId = recordId;
            cdl.ContentDocumentId = contentDocumentId;
            cdl.ShareType = 'I';
            cdl.Visibility = 'AllUsers';
            insert cdl;
        }

        return contentDocumentId;
    }

    /**
     * Creates a public link (ContentDistribution) for the latest published version of the file.
     * Returns a wrapper containing the distribution record Id and public URL.
     */
    @AuraEnabled
    public static DistributionWrapper createPublicLink(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw new AuraHandledException('Content Document ID is required.');
        }

        ContentDocument doc = [
            SELECT Id, LatestPublishedVersionId 
            FROM ContentDocument 
            WHERE Id = :contentDocumentId
            LIMIT 1
        ];

        ContentDistribution cd = new ContentDistribution();
        cd.Name = 'Public Link';
        cd.ContentVersionId = doc.LatestPublishedVersionId;
        cd.PreferencesAllowViewInBrowser = true;
        cd.PreferencesAllowOriginalDownload = true;
        cd.PreferencesLinkLatestVersion = true; // Ensures the latest version is linked
        cd.PreferencesPasswordRequired = false;
        insert cd;

        // Query again to get the DistributionPublicUrl after insert
        cd = [
            SELECT Id, DistributionPublicUrl 
            FROM ContentDistribution 
            WHERE Id = :cd.Id
            LIMIT 1
        ];

        DistributionWrapper wrap = new DistributionWrapper();
        wrap.distributionId = cd.Id;
        wrap.distributionPublicUrl = cd.DistributionPublicUrl;
        return wrap;
    }

    /**
     * Retrieves the latest ContentVersionId for a given ContentDocumentId.
     */
    @AuraEnabled
    public static String getLatestContentVersionId(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw new AuraHandledException('Content Document ID is required.');
        }

        ContentVersion cv = [
            SELECT Id 
            FROM ContentVersion 
            WHERE ContentDocumentId = :contentDocumentId
            ORDER BY VersionNumber DESC 
            LIMIT 1
        ];

        return cv.Id;
    }

    /**
     * Deletes the file from Salesforce:
     *  1) Deletes the ContentDistribution record (to remove the public link).
     *  2) If recordId is present, only delete the ContentDocumentLink to that record.
     *  3) If recordId is not present, delete the entire ContentDocument.
     */
    @AuraEnabled
    public static void deleteFile(Id contentDocumentId, Id recordId, Id distributionId) {
        if (contentDocumentId == null) {
            throw new AuraHandledException('Content Document ID is required.');
        }

        // 1) Delete the public link
        if (distributionId != null) {
            try {
                ContentDistribution dist = [
                    SELECT Id 
                    FROM ContentDistribution 
                    WHERE Id = :distributionId
                    LIMIT 1
                ];
                delete dist;
            } catch (QueryException e) {
                // Distribution record might have already been deleted
                System.debug('ContentDistribution not found or already deleted.');
            }
        }

        // 2) If recordId is present, only delete the link
        //    Otherwise, delete the entire ContentDocument
        if (recordId != null) {
            List<ContentDocumentLink> links = [
                SELECT Id 
                FROM ContentDocumentLink 
                WHERE ContentDocumentId = :contentDocumentId
                AND LinkedEntityId = :recordId
            ];
            if (!links.isEmpty()) {
                delete links;
            }
        } else {
            // If no recordId, delete the entire ContentDocument
            try {
                ContentDocument cd = [
                    SELECT Id 
                    FROM ContentDocument 
                    WHERE Id = :contentDocumentId
                    LIMIT 1
                ];
                delete cd;
            } catch (QueryException e) {
                throw new AuraHandledException('Content Document not found.');
            }
        }
    }

    // Simple wrapper to return from createPublicLink
    public class DistributionWrapper {
        @AuraEnabled public Id distributionId;
        @AuraEnabled public String distributionPublicUrl;
    }
}
