--[[
作者：小特_XT、DeepSeek
说明：如果你发现你的FA网页无法访问摄像头，那么下面这段代码在你的浏览器页面运行，可以让网页能正常打开(访问)摄像头
]]



require "import"
import "android.content.Intent"
import "android.net.Uri"
import "android.provider.MediaStore"
import "java.io.File"

-- 设置 WebChromeClient
webView.setWebChromeClient(luajava.override(WebChromeClient,{
    onPermissionRequest = function(_, request)
        -- 允许所有请求（包括视频捕获、音频捕获），否则网页会报错
        -- 这里建议加个权限请求弹窗，否则网页可以随意打开摄像头，很危险
        -- 因为懒我就不整了
        request.grant(request.getResources())
    end,
  
    -- 拍照拦截(fa2如果直接请求是无效的)，直接调相机
    onShowFileChooser = function(a, view, valueCallback, fileChooserParams)
        -- 生成照片存储路径
        local photoFile = File(activity.getExternalCacheDir(), "webcam_" .. os.time() .. ".jpg")
        local photoUri
        -- 尝试用 FileProvider 获取 content URI（兼容高版本）
        local success, result = pcall(function()
            return FileProvider.getUriForFile(activity, activity.getPackageName() .. ".fileprovider", photoFile)
        end)
        if success then
            photoUri = result
        else
            -- 降级：直接用 file:// URI（低版本可用），这里是AI提供的，不知道有没有用，我没测
            photoUri = Uri.fromFile(photoFile)
        end
        
        -- 启动相机
        local intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
        intent.putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
        intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        if intent.resolveActivity(activity.getPackageManager()) ~= nil then
            activity.startActivity(intent)
            
            -- 用定时器等待照片生成，然后回传给网页，这里来自AI
            local checkCount = 0
            local maxCheck = 30  -- 最多等 3 秒
            local timerId = nil
            timerId = timer.schedule(function()
                checkCount = checkCount + 1
                if photoFile:exists() and photoFile:length() > 0 then
                    -- 照片已生成，回调给网页
                    local results = { photoUri }
                    valueCallback.onReceiveValue(results)
                    -- 停止定时器
                    if timerId then
                        timer:cancel(timerId)
                    end
                elseif checkCount >= maxCheck then
                    -- 超时，传空值
                    valueCallback.onReceiveValue(nil)
                    if timerId then
                        timer:cancel(timerId)
                    end
                end
            end, 100, true)  -- 每 100ms 检查一次
        else
            -- 没有相机应用
            valueCallback.onReceiveValue(nil)
        end
        return true
    end
}))

--下面是一段测试html，各位可以复制到fa中自行测试
--[[
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>相机拍照 + 录音测试</title>
    <style>
        #video { border: 1px solid #ccc; }
        #canvas { display: none; }
        #photo { max-width: 640px; margin-top: 10px; border: 1px solid #ccc; display: none; }
        .section { margin: 15px 0; }
    </style>
</head>
<body>
    <h2>相机拍照 + 录音测试</h2>

    <!-- ========== 拍照区域 ========== -->
    <div class="section">
        <video id="video" width="640" height="480" autoplay muted></video>
        <canvas id="canvas" width="640" height="480"></canvas>
        <br>
        <button id="startCameraBtn">打开相机</button>
        <button id="captureBtn" disabled>拍照</button>
        <br>
        <img id="photo" />
    </div>

    <hr>

    <!-- ========== 录音区域 ========== -->
    <div class="section">
        <button id="startRecordBtn">开始录音</button>
        <button id="stopRecordBtn" disabled>停止录音</button>
        <button id="playRecordBtn" disabled>播放录音</button>
        <button id="downloadRecordBtn" disabled>下载录音</button>
        <br>
        <span id="recordingStatus" style="color:red;"></span>
        <audio id="audioPlayer" controls style="margin-top:5px; display:none;"></audio>
    </div>

    <script>
        // ==================== 拍照逻辑 ====================
        const video = document.getElementById('video');
        const canvas = document.getElementById('canvas');
        const ctx = canvas.getContext('2d');
        const startCameraBtn = document.getElementById('startCameraBtn');
        const captureBtn = document.getElementById('captureBtn');
        const photo = document.getElementById('photo');
        let cameraStream = null;

        startCameraBtn.onclick = async () => {
            try {
                cameraStream = await navigator.mediaDevices.getUserMedia({ 
                    video: { facingMode: "environment" }, 
                    audio: false 
                });
                video.srcObject = cameraStream;
                startCameraBtn.disabled = true;
                captureBtn.disabled = false;
            } catch (err) {
                alert('无法打开相机: ' + err.message);
                console.error(err);
            }
        };

        captureBtn.onclick = () => {
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
            const dataUrl = canvas.toDataURL('image/jpeg', 0.9);
            photo.src = dataUrl;
            photo.style.display = 'block';
        };

        // ==================== 录音逻辑 ====================
        const startRecordBtn = document.getElementById('startRecordBtn');
        const stopRecordBtn = document.getElementById('stopRecordBtn');
        const playRecordBtn = document.getElementById('playRecordBtn');
        const downloadRecordBtn = document.getElementById('downloadRecordBtn');
        const recordingStatus = document.getElementById('recordingStatus');
        const audioPlayer = document.getElementById('audioPlayer');
        let mediaRecorder = null;
        let audioChunks = [];
        let audioBlob = null;
        let audioUrl = null;

        startRecordBtn.onclick = async () => {
            try {
                // 仅获取音频流
                const audioStream = await navigator.mediaDevices.getUserMedia({ 
                    audio: true 
                });
                
                mediaRecorder = new MediaRecorder(audioStream);
                audioChunks = [];

                mediaRecorder.ondataavailable = (event) => {
                    if (event.data.size > 0) {
                        audioChunks.push(event.data);
                    }
                };

                mediaRecorder.onstop = () => {
                    audioBlob = new Blob(audioChunks, { type: 'audio/webm' });
                    audioUrl = URL.createObjectURL(audioBlob);
                    audioPlayer.src = audioUrl;
                    audioPlayer.style.display = 'block';
                    playRecordBtn.disabled = false;
                    downloadRecordBtn.disabled = false;
                    // 释放音频流轨道
                    audioStream.getTracks().forEach(track => track.stop());
                };

                mediaRecorder.start();
                recordingStatus.textContent = '● 正在录音...';
                startRecordBtn.disabled = true;
                stopRecordBtn.disabled = false;
                playRecordBtn.disabled = true;
                downloadRecordBtn.disabled = true;
                audioPlayer.style.display = 'none';
            } catch (err) {
                alert('无法启动录音: ' + err.message);
                console.error(err);
            }
        };

        stopRecordBtn.onclick = () => {
            if (mediaRecorder && mediaRecorder.state !== 'inactive') {
                mediaRecorder.stop();
                recordingStatus.textContent = '录音已停止';
                startRecordBtn.disabled = false;
                stopRecordBtn.disabled = true;
            }
        };

        playRecordBtn.onclick = () => {
            if (audioUrl) {
                audioPlayer.play();
            }
        };

        downloadRecordBtn.onclick = () => {
            if (audioBlob) {
                const a = document.createElement('a');
                a.href = audioUrl;
                a.download = 'recording.webm';
                a.click();
            }
        };
    </script>
</body>
</html>
]]
