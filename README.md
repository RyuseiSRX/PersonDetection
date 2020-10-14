# PersonDetection

This application has 4 components to achieve task (Mark people in video and record for 10 seconds whenever a person is detected in the source mp4 video)

1. VideoFileCapture
- This class use AVAssetReader to access the video track in a video file from main bundle
- Use AVAssetReaderTrackOutput to continuously each sample buffer from this track and pass it to ProcessVideoFileViewController

2. ProcessVideoFileViewController
- ProcessVideoFileViewController provide two actions for you, one is a player for source video, the other is the event detector
- Initiate a VideoFileCapture when the detector is started
- Pass CMSampleBuffer from VideoFileCapture to VNCoreMLRequest then handle it by VNImageRequestHandler
- Whenever a person is detected, start to append marked CMSampleBuffers to EventVideoRecorder for 10 seconds
- Export a video whenever it reaches its limit or there are no more frames to handle
- Display a finish alert when video is finished processed.

3. ObjectMarkerDrawer
- Copy the content from an input CVPixelBuffer, then draw rectangle and text for each observation from input VNRecognizedObjectObservation array
- Return the processed CVPixelBuffer

4. EventVideoRecorder
- Define the output format and destination
- Take CVPixelBuffer and the timestamp from ProcessVideoFileViewController to calculate the presentation time in output video, then append the content of CVPixelBuffer into AVAssetWriterInputPixelBufferAdaptor
- EventVideoRecorder is responsible for controlling the length of video file and export video file to album (PHPhotoLibrary)

