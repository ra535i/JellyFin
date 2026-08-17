/* eslint-disable */
const vaapiPrefix = ` -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 -hwaccel_output_format vaapi `;

const details = () => {
  return {
    id: `Tdarr_Plugin_Seth_VAAPI_HEVC_20Mbps`,
    Stage: 'Pre-processing',
    Name: `Seth's VAAPI HEVC Transcode (20Mbps cap)`,
    Type: `Video`,
    Operation: `Transcode`,
    Description: `Transcodes non-HEVC video to HEVC via VAAPI, targeting 50%% of input bitrate but capped at 20Mbps. ` +
      `Keeps all audio/subtitle streams, passes through HDR metadata.`,
    Version: `1.0`,
    Tags: `pre-processing,ffmpeg,video only,h265,configurable,vaapi`,
    Inputs: [{
      name: `minBitrate`,
      type: 'string',
      defaultValue:'25000',
      inputUI: {
        type: 'text',
      },
      tooltip: `Minimum bitrate threshold in kbps. Files below this won't be processed. Leave blank to disable.`
    }]
  }
}

const plugin = (file, librarySettings, inputs, otherArguments) => {
    const lib = require('../methods/lib')();
  inputs = lib.loadDefaultValues(inputs, details);
  var response = {
    processFile: false,
    preset: ``,
    handBrakeMode: false,
    FFmpegMode: true,
    reQueueAfter: false,
    infoLog: ``
  };

  var videoProcessingRequired = false;
  var ffmpegParameters = ``;
  var duration = 0;
  var currentBitrate = 0;
  var targetBitrate = 0;

  if (file.fileMedium !== `video`) {
    response.infoLog += `☒ File is not a video. Unable to process.\n`;
    return response;
  }

  file.ffProbeData.streams.forEach(function(stream) {
    if (stream.codec_type == `video`) {
      if (stream.codec_name !== `mjpeg` && stream.codec_name !== `hevc`) {
        videoProcessingRequired = true;

        if (parseFloat(file.ffProbeData?.format?.duration) > 0) {
            duration = parseFloat(file.ffProbeData?.format?.duration) * 0.0166667;
        } else if(file.meta.Duration !== `undefined`){
            duration = file.meta.Duration * 0.0166667;
        } else {
          duration = stream.duration * 0.0166667;
        }

        currentBitrate = ~~(file.file_size / (duration * 0.0075));
        // Target half of input bitrate, but cap at 20Mbps (20000 kbps)
        targetBitrate = Math.min(~~(currentBitrate / 2), 20000);

        if (targetBitrate < 1000) {
          response.infoLog += `☒ Calculated target bitrate ${targetBitrate}kbps is too low. Skipping.\n`;
          return response;
        }

        if (inputs.minBitrate !== `` && currentBitrate <= parseInt(inputs.minBitrate)) {
          response.infoLog += `☒ Input file bitrate ${currentBitrate}kbps is below minimum ${inputs.minBitrate}kbps. Skipping.\n`;
          return response;
        }

        response.infoLog += `☒ Input bitrate: ${currentBitrate}kbps → Target: ${targetBitrate}kbps (capped at 20Mbps).\n`;
        ffmpegParameters += ` -c:v:0 hevc_vaapi -b:v ${targetBitrate}k -minrate ${~~(targetBitrate*0.7)}k ` +
          `-maxrate ${~~(targetBitrate*1.3)}k -bufsize 1M -max_muxing_queue_size 1024 `;
      }
    }
  });

  if (videoProcessingRequired) {
    response.infoLog += `☑ Stream analysis complete, processing required.\n`;
    // Map all streams: video, audio, subtitles, attachments, chapters - copy non-video
    response.preset = `${vaapiPrefix},-map 0:v -map 0:a -map 0:s? -map 0:d? -map 0:t? -c copy -c:v:0 hevc_vaapi -b:v ${targetBitrate}k -minrate ${~~(targetBitrate*0.7)}k -maxrate ${~~(targetBitrate*1.3)}k -bufsize 1M -max_muxing_queue_size 1024`;
    response.container = `${file.container}`;
    response.processFile = true;
  } else {
    response.infoLog += `☑ Stream is already HEVC or no video stream found. No processing needed.\n`;
  }
  return response;
}

module.exports.details = details;
module.exports.plugin = plugin;