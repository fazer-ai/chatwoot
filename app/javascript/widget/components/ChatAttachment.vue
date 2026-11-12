<script>
import FileUpload from 'vue-upload-component';
import Spinner from 'shared/components/Spinner.vue';
import {
  checkFileSizeLimit,
  resolveMaximumFileUploadSize,
} from 'shared/helpers/FileHelper';
import { ALLOWED_FILE_TYPES } from 'shared/constants/messages';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import { DirectUpload } from 'activestorage';
import { mapGetters } from 'vuex';
import { emitter } from 'shared/helpers/mitt';
import { useAttachments } from '../composables/useAttachments';
import { useScreenCapture } from '../composables/useScreenCapture';
import { isEditableImage } from '../helpers/imageEditor';
import ImageEditor from './ImageEditor.vue';

export default {
  components: { FluentIcon, FileUpload, ImageEditor, Spinner },
  props: {
    onAttach: {
      type: Function,
      default: () => {},
    },
  },
  setup() {
    const { canHandleAttachments } = useAttachments();
    const { isScreenCaptureSupported, captureScreen } = useScreenCapture();
    return { canHandleAttachments, isScreenCaptureSupported, captureScreen };
  },
  data() {
    return { isUploading: false, imageToEdit: null };
  },
  computed: {
    ...mapGetters({
      globalConfig: 'globalConfig/get',
    }),
    fileUploadSizeLimit() {
      return resolveMaximumFileUploadSize(
        this.globalConfig.maximumFileUploadSize
      );
    },
    allowedFileTypes() {
      return ALLOWED_FILE_TYPES;
    },
  },
  mounted() {
    document.addEventListener('paste', this.handleClipboardPaste);
  },
  unmounted() {
    document.removeEventListener('paste', this.handleClipboardPaste);
  },
  methods: {
    handleClipboardPaste(e) {
      // If file picker is not enabled, do not allow paste
      if (!this.canHandleAttachments) return;
      // The editor already holds an image; a paste would replace it unseen.
      if (this.imageToEdit) return;

      const items = (e.clipboardData || e.originalEvent.clipboardData).items;
      // items is a DataTransferItemList object which does not have forEach method
      const itemsArray = Array.from(items);
      itemsArray.forEach(item => {
        if (item.kind === 'file') {
          e.preventDefault();
          const file = item.getAsFile();
          this.$refs.upload.add(file);
        }
      });
    },
    getFileType(fileType) {
      return fileType.includes('image') ? 'image' : 'file';
    },
    onFileUpload(file) {
      if (file && isEditableImage(file.type)) {
        this.imageToEdit = file.file;
        return;
      }
      this.uploadFile(file);
    },
    onEditorSave(file) {
      this.imageToEdit = null;
      this.uploadFile({
        file,
        name: file.name,
        type: file.type,
        size: file.size,
      });
    },
    onEditorCancel() {
      this.imageToEdit = null;
    },
    async onCaptureScreen() {
      try {
        const file = await this.captureScreen();
        if (file) this.imageToEdit = file;
      } catch (error) {
        emitter.emit(BUS_EVENTS.SHOW_ALERT, {
          message: this.$t('SCREEN_CAPTURE.ERROR'),
        });
      }
    },
    async uploadFile(file) {
      if (this.globalConfig.directUploadsEnabled) {
        await this.onDirectFileUpload(file);
      } else {
        await this.onIndirectFileUpload(file);
      }
    },
    async onDirectFileUpload(file) {
      if (!file) {
        return;
      }
      this.isUploading = true;
      try {
        if (checkFileSizeLimit(file, this.fileUploadSizeLimit)) {
          const { websiteToken } = window.chatwootWebChannel;
          const upload = new DirectUpload(
            file.file,
            `/api/v1/widget/direct_uploads?website_token=${websiteToken}`,
            {
              directUploadWillCreateBlobWithXHR: xhr => {
                xhr.setRequestHeader('X-Auth-Token', window.authToken);
              },
            }
          );

          upload.create((error, blob) => {
            if (error) {
              emitter.emit(BUS_EVENTS.SHOW_ALERT, {
                message: error,
              });
            } else {
              this.onAttach({
                file: blob.signed_id,
                ...this.getLocalFileAttributes(file),
              });
            }
          });
        } else {
          emitter.emit(BUS_EVENTS.SHOW_ALERT, {
            message: this.$t('FILE_SIZE_LIMIT', {
              MAXIMUM_FILE_UPLOAD_SIZE: this.fileUploadSizeLimit,
            }),
          });
        }
      } catch (error) {
        // Error
      }
      this.isUploading = false;
    },
    async onIndirectFileUpload(file) {
      if (!file) {
        return;
      }
      this.isUploading = true;
      try {
        if (checkFileSizeLimit(file, this.fileUploadSizeLimit)) {
          await this.onAttach({
            file: file.file,
            ...this.getLocalFileAttributes(file),
          });
        } else {
          emitter.emit(BUS_EVENTS.SHOW_ALERT, {
            message: this.$t('FILE_SIZE_LIMIT', {
              MAXIMUM_FILE_UPLOAD_SIZE: this.fileUploadSizeLimit,
            }),
          });
        }
      } catch (error) {
        // Error
      }
      this.isUploading = false;
    },
    getLocalFileAttributes(file) {
      return {
        thumbUrl: window.URL.createObjectURL(file.file),
        fileType: this.getFileType(file.type),
      };
    },
  },
};
</script>

<template>
  <div class="flex items-center">
    <FileUpload
      ref="upload"
      :size="4096 * 2048"
      :accept="allowedFileTypes"
      :data="{
        direct_upload_url: '/api/v1/widget/direct_uploads',
        direct_upload: true,
      }"
      @input-file="onFileUpload"
    >
      <button class="min-h-8 min-w-8 flex items-center justify-center">
        <FluentIcon v-if="!isUploading.image" icon="attach" />
        <Spinner v-if="isUploading" size="small" />
      </button>
    </FileUpload>
    <button
      v-if="isScreenCaptureSupported"
      class="min-h-8 min-w-8 flex items-center justify-center"
      :aria-label="$t('SCREEN_CAPTURE.BUTTON')"
      :title="$t('SCREEN_CAPTURE.BUTTON')"
      @click="onCaptureScreen"
    >
      <span class="i-lucide-camera size-5" />
    </button>
    <ImageEditor
      v-if="imageToEdit"
      :file="imageToEdit"
      @save="onEditorSave"
      @cancel="onEditorCancel"
    />
  </div>
</template>
