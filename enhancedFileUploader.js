import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import uploadFile from '@salesforce/apex/FileUploadController.uploadFile';
import createPublicLink from '@salesforce/apex/FileUploadController.createPublicLink';
import deleteFile from '@salesforce/apex/FileUploadController.deleteFile';
import getLatestContentVersionId from '@salesforce/apex/FileUploadController.getLatestContentVersionId';

export default class FileUpload extends LightningElement {
    @api recordId;

    @api fileTypes = '*';

    @track filePreviews = [];

    @api contentDocumentIds = [];

    // Handle file selection
    handleFileChange(event) {
        const files = event.target.files;
        if (!files || files.length === 0) {
            return;
        }

        for (let i = 0; i < files.length; i++) {
            const file = files[i];
            // Check size limit of 2GB (adjusted in Apex for guest users)
            if (file.size > 2 * 1024 * 1024 * 1024) {
                // Replace alert with a toast or custom error as desired
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'File size exceeds the 2GB limit',
                        variant: 'error',
                    })
                );
                continue;
            }

            // Generate a temporary unique identifier for each file
            const tempId = `${file.name}-${file.size}-${file.lastModified}-${Math.random()}`;

            // Initialize the file preview with initial progress and uploading state
            this.filePreviews = [
                ...this.filePreviews,
                {
                    tempId: tempId, // Temporary identifier
                    name: file.name,
                    isUploading: true,
                    progress: 0,
                    isImage: this.isImage(file.type),
                    isPdf: this.isPdf(file.type),
                    showIcon: false,
                    altText: '',
                    deleteLabel: `Delete ${file.name}`,
                    previewUrl: '',
                    distributionId: null
                }
            ];

            // Read the file as base64
            const reader = new FileReader();
            reader.onload = () => {
                const base64 = reader.result.split(',')[1];
                this.uploadToSalesforce(file, base64, tempId);
            };
            reader.onprogress = (event) => {
                if (event.lengthComputable) {
                    const progress = Math.round((event.loaded / event.total) * 100);
                    this.updateFileProgress(tempId, progress);
                }
            };
            reader.readAsDataURL(file);
        }
    }

    // Upload file to Salesforce, create public link for PDFs, and display preview
    async uploadToSalesforce(file, base64, tempId) {
        try {
            // 1) Upload file (ContentVersion -> ContentDocument)
            const contentDocumentId = await uploadFile({
                fileName: file.name,
                base64Data: base64,
                recordId: this.recordId
            });

            // If there's no record ID, store ContentDocumentId for flows
            if (!this.recordId) {
                this.contentDocumentIds = [...this.contentDocumentIds, contentDocumentId];
            }

            // 2) Determine if the file is an image or PDF
            const isImage = this.isImage(file.type);
            const isPdf = this.isPdf(file.type);

            let previewUrl = null;
            let distributionId = null;
            let altText = null;

            if (isPdf) {
                // 3a) Create public link for PDFs
                const distributionResult = await createPublicLink({ contentDocumentId });
                distributionId = distributionResult.distributionId;
                previewUrl = distributionResult.distributionPublicUrl;
            } else if (isImage) {
                // 3b) Construct internal Salesforce URL for images
                const contentVersionId = await getLatestContentVersionId({ contentDocumentId });
                if (contentVersionId) {
                    previewUrl = `/sfc/servlet.shepherd/version/download/${contentVersionId}`;
                    altText = `Preview of ${file.name}`;
                } else {
                    console.warn(`No ContentVersion found for ContentDocumentId: ${contentDocumentId}`);
                }
            }

            // 4) Update the file preview with the final details
            this.filePreviews = this.filePreviews.map(filePreview => {
                if (filePreview.tempId === tempId) {
                    return {
                        ...filePreview,
                        id: contentDocumentId, // Replace tempId with actual ContentDocumentId
                        isUploading: false,
                        progress: 100,
                        previewUrl: previewUrl,
                        distributionId: distributionId,
                        altText: altText,
                        showIcon: !isImage && !isPdf && !previewUrl
                    };
                }
                return filePreview;
            });
        } catch (error) {
            console.error('Error uploading file:', error);
            this.filePreviews = this.filePreviews.map(filePreview => {
                if (filePreview.tempId === tempId) {
                    return {
                        ...filePreview,
                        isUploading: false,
                        progress: 0,
                        showIcon: true // Show fallback icon on error
                    };
                }
                return filePreview;
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error uploading file',
                    message: error.body ? error.body.message : error.message,
                    variant: 'error',
                })
            );
        }
    }

    // Update the progress of a specific file
    updateFileProgress(tempId, progress) {
        this.filePreviews = this.filePreviews.map(filePreview => {
            if (filePreview.tempId === tempId) {
                return {
                    ...filePreview,
                    progress: progress
                };
            }
            return filePreview;
        });
    }

    // Identify if the file is an image
    isImage(mimeType) {
        return mimeType.startsWith('image/');
    }

    // Identify if the file is a PDF
    isPdf(mimeType) {
        return mimeType === 'application/pdf';
    }

    // Handle deletion of the file from previews and Salesforce
    handleDelete(event) {
        const contentDocumentId = event.target.dataset.id;
        const distributionId = event.target.dataset.distributionid;

        // Find file in the preview list
        const index = this.filePreviews.findIndex(file => file.id === contentDocumentId);
        if (index === -1) return;

        // Remove from local preview
        const updatedFilePreviews = [...this.filePreviews];
        updatedFilePreviews.splice(index, 1);
        this.filePreviews = updatedFilePreviews;

        // Remove from contentDocumentIds if we had stored it for a flow
        if (!this.recordId) {
            this.contentDocumentIds = this.contentDocumentIds.filter(id => id !== contentDocumentId);
        }

        // Call Apex to delete the file from Salesforce
        deleteFile({
            contentDocumentId: contentDocumentId,
            recordId: this.recordId,
            distributionId: distributionId
        })
        .then(() => {
            console.log('File deleted successfully');
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'File deleted successfully',
                    variant: 'success',
                })
            );
        })
        .catch(error => {
            console.error('Error deleting file:', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error deleting file',
                    message: error.body ? error.body.message : error.message,
                    variant: 'error',
                })
            );
        });
    }
}