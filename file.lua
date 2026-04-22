--[[
╔══════════════════════════════════════════════════════════════╗
║     MOVEMENT STUDIO v2 — Gravador + Reprodutor Roblox       ║
║                                                              ║
║ INSTALAR:                                                    ║
║   StarterPlayer → StarterCharacterScripts → LocalScript      ║
║                                                              ║
║ FLUXO:                                                       ║
║   1. Grave com F ou botão REC                                ║
║   2. Gere o código com K ou botão EXPORT                     ║
║   3. Cole esse código na caixa quando quiser reutilizar      ║
║   4. Clique em LOAD e depois PLAY                            ║
║                                                              ║
║ TECLAS:                                                      ║
║   F = gravar/parar                                           ║
║   G = play/stop                                              ║
║   H = pause/retomar                                          ║
║   J = limpar tudo                                            ║
║   K = exportar código                                        ║
║   L = alternar loop                                          ║
║   + / - = velocidade                                         ║
╚══════════════════════════════════════════════════════════════╝
--]]

-- Opcional: cole um path exportado aqui para carregar ao iniciar.
local PATH_DATA = nil

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService   = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Character   = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid    = Character:WaitForChild("Humanoid")
local RootPart    = Character:WaitForChild("HumanoidRootPart")

-- ─── Constantes ──────────────────────────────────────────────────────────────

local RECORD_FPS    = 30                -- FPS de captura (era 20)
local RECORD_INTERVAL = 1 / RECORD_FPS
local PLAYBACK_SPEEDS = {0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3}
local EXPORT_START  = "-- PATH_EXPORT_BEGIN"
local EXPORT_END    = "-- PATH_EXPORT_END"

-- ─── Estado ──────────────────────────────────────────────────────────────────

local frames        = {}
local importedPath  = PATH_DATA
local activeSource  = "recorded"
local gravando      = false
local reproduzindo  = false
local pausado       = false
local loopAtivo     = false
local velocidadeIndex = 4
local frameAtual    = 0
local ultimoFrameTime = 0
local ultimoNoAr    = false
local tempoInicioReproducao = 0
local tempoPausadoAcumulado = 0
local tempoInicioPausa = 0
local playbackPartStates = {}
local playbackHumanoidState = nil
local playbackRigPrepared = false
local conexaoGravacao  = nil
local conexaoReproducao = nil

-- Referências de UI (declaradas antes de uso)
local statusDot, statusLbl, detailsLbl
local speedChip, loopChip, sourceChip
local progressFill, progressLbl
local recBtn, playBtn, pauseBtn, loopBtn
local loadBtn, exportBtn, clearBtn, speedDownBtn, speedUpBtn
local outputBox, noticeLbl

-- ─── Personagem ──────────────────────────────────────────────────────────────

local function refreshCharacter()
    Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    Humanoid  = Character:FindFirstChildOfClass("Humanoid") or Character:WaitForChild("Humanoid")
    RootPart  = Character:FindFirstChild("HumanoidRootPart") or Character:WaitForChild("HumanoidRootPart")
end

LocalPlayer.CharacterAdded:Connect(function(c)
    Character = c
    Humanoid  = c:WaitForChild("Humanoid")
    RootPart  = c:WaitForChild("HumanoidRootPart")
    playbackPartStates  = {}
    playbackHumanoidState = nil
    playbackRigPrepared = false
end)

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function getPlaybackSpeed()
    return PLAYBACK_SPEEDS[velocidadeIndex]
end

local function getPathForSource(source)
    if source == "imported" then
        return importedPath, "caixa"
    end
    if #frames > 0 then
        return {fps = RECORD_FPS, f = frames}, "gravacao"
    end
    if importedPath then
        return importedPath, "caixa"
    end
    return nil, "nenhuma"
end

local function getActivePath()
    return getPathForSource(activeSource)
end

-- ─── Validação ───────────────────────────────────────────────────────────────
-- Frame agora tem 8 campos: x,y,z, qx,qy,qz,qw, jump

local function validarFrame(f)
    if type(f) ~= "table" or #f ~= 8 then return false end
    for i = 1, 8 do
        if type(f[i]) ~= "number" then return false end
    end
    return true
end

-- Compatibilidade com frames antigos de 6 campos
local function validarFrameLegacy(f)
    return type(f) == "table" and #f == 6
        and type(f[1]) == "number" and type(f[2]) == "number"
        and type(f[3]) == "number" and type(f[4]) == "number"
        and type(f[5]) == "number" and type(f[6]) == "number"
end

local function validarPath(path)
    if path == nil then return false, "Nenhum PATH carregado." end
    if type(path) ~= "table" then return false, "PATH invalido: precisa ser tabela." end
    if type(path.fps) ~= "number" or type(path.f) ~= "table" then
        return false, "PATH invalido: formato incorreto."
    end
    if path.fps <= 0 then return false, "PATH invalido: fps deve ser > 0." end
    if #path.f == 0 then return false, "PATH vazio." end
    for i, frame in ipairs(path.f) do
        if not validarFrame(frame) and not validarFrameLegacy(frame) then
            return false, ("Frame %d invalido."):format(i)
        end
    end
    return true, "OK"
end

-- ─── Física / Rig ────────────────────────────────────────────────────────────

local function setFisica(ativa)
    if not Humanoid then return end
    if ativa then
        Humanoid.WalkSpeed    = (playbackHumanoidState and playbackHumanoidState.WalkSpeed) or 16
        Humanoid.AutoRotate   = (playbackHumanoidState and playbackHumanoidState.AutoRotate) ~= false
        Humanoid.JumpPower    = (playbackHumanoidState and playbackHumanoidState.JumpPower) or 50
        Humanoid.PlatformStand = false
    else
        playbackHumanoidState = {
            WalkSpeed    = Humanoid.WalkSpeed,
            AutoRotate   = Humanoid.AutoRotate,
            JumpPower    = Humanoid.JumpPower,
            PlatformStand = Humanoid.PlatformStand,
        }
        Humanoid.WalkSpeed    = 0
        Humanoid.AutoRotate   = false
        Humanoid.JumpPower    = 0
        Humanoid.PlatformStand = false
    end
end

local function estaNoAr()
    local s = Humanoid:GetState()
    return s == Enum.HumanoidStateType.Jumping or s == Enum.HumanoidStateType.Freefall
end

local function prepararRigParaPlayback()
    playbackRigPrepared = true
    playbackPartStates  = {}
    for _, desc in ipairs(Character:GetDescendants()) do
        if desc:IsA("BasePart") then
            playbackPartStates[desc] = {
                Anchored  = desc.Anchored,
                CanCollide = desc.CanCollide,
            }
            desc.CanCollide = false
            desc.AssemblyLinearVelocity  = Vector3.zero
            desc.AssemblyAngularVelocity = Vector3.zero
        end
    end
    setFisica(false)
end

local function restaurarRigDepoisPlayback()
    if not playbackRigPrepared then return end
    for part, state in pairs(playbackPartStates) do
        if part and part.Parent then
            part.Anchored   = state.Anchored
            part.CanCollide = state.CanCollide
            part.AssemblyLinearVelocity  = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
        end
    end
    playbackPartStates = {}
    setFisica(true)
    if Humanoid then
        Humanoid.PlatformStand = false
        Humanoid:ChangeState(Enum.HumanoidStateType.Running)
    end
    playbackHumanoidState = nil
    playbackRigPrepared   = false
end

-- ─── CFrame helpers ──────────────────────────────────────────────────────────

-- Converte CFrame para quaternion (x,y,z,w)
local function cfToQuat(cf)
    local rx, ry, rz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
    local trace = r00 + r11 + r22
    local qx, qy, qz, qw
    if trace > 0 then
        local s = 0.5 / math.sqrt(trace + 1)
        qw = 0.25 / s
        qx = (r21 - r12) * s
        qy = (r02 - r20) * s
        qz = (r10 - r01) * s
    elseif r00 > r11 and r00 > r22 then
        local s = 2 * math.sqrt(1 + r00 - r11 - r22)
        qw = (r21 - r12) / s
        qx = 0.25 * s
        qy = (r01 + r10) / s
        qz = (r02 + r20) / s
    elseif r11 > r22 then
        local s = 2 * math.sqrt(1 + r11 - r00 - r22)
        qw = (r02 - r20) / s
        qx = (r01 + r10) / s
        qy = 0.25 * s
        qz = (r12 + r21) / s
    else
        local s = 2 * math.sqrt(1 + r22 - r00 - r11)
        qw = (r10 - r01) / s
        qx = (r02 + r20) / s
        qy = (r12 + r21) / s
        qz = 0.25 * s
    end
    return qx, qy, qz, qw
end

-- Constrói CFrame a partir de posição + quaternion
local function cfFromPosQuat(x, y, z, qx, qy, qz, qw)
    -- normaliza quaternion
    local len = math.sqrt(qx*qx + qy*qy + qz*qz + qw*qw)
    if len < 0.0001 then qw = 1; qx = 0; qy = 0; qz = 0; len = 1 end
    qx, qy, qz, qw = qx/len, qy/len, qz/len, qw/len
    local r00 = 1 - 2*(qy*qy + qz*qz)
    local r01 = 2*(qx*qy - qz*qw)
    local r02 = 2*(qx*qz + qy*qw)
    local r10 = 2*(qx*qy + qz*qw)
    local r11 = 1 - 2*(qx*qx + qz*qz)
    local r12 = 2*(qy*qz - qx*qw)
    local r20 = 2*(qx*qz - qy*qw)
    local r21 = 2*(qy*qz + qx*qw)
    local r22 = 1 - 2*(qx*qx + qy*qy)
    return CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end

-- SLERP de quaternions para rotação suave
local function slerpQuat(ax, ay, az, aw, bx, by, bz, bw, t)
    local dot = ax*bx + ay*by + az*bz + aw*bw
    -- escolhe caminho mais curto
    if dot < 0 then
        bx, by, bz, bw = -bx, -by, -bz, -bw
        dot = -dot
    end
    if dot > 0.9995 then
        -- interpolação linear para quaternions muito próximos
        local rx = ax + t*(bx - ax)
        local ry = ay + t*(by - ay)
        local rz = az + t*(bz - az)
        local rw = aw + t*(bw - aw)
        local len = math.sqrt(rx*rx + ry*ry + rz*rz + rw*rw)
        return rx/len, ry/len, rz/len, rw/len
    end
    local theta0 = math.acos(dot)
    local theta  = theta0 * t
    local sinT0  = math.sin(theta0)
    local sinT   = math.sin(theta)
    local s0 = math.cos(theta) - dot * sinT / sinT0
    local s1 = sinT / sinT0
    return
        s0*ax + s1*bx,
        s0*ay + s1*by,
        s0*az + s1*bz,
        s0*aw + s1*bw
end

-- Converte frame legado (6 campos: x,y,z,lx,lz,jump) para o novo formato
local function upgradeFrameLegacy(f)
    local lx, lz = f[4], f[5]
    local flat = Vector3.new(lx, 0, lz)
    if flat.Magnitude < 0.001 then flat = Vector3.new(0, 0, -1) else flat = flat.Unit end
    local cf = CFrame.lookAt(Vector3.new(f[1], f[2], f[3]), Vector3.new(f[1], f[2], f[3]) + flat)
    local qx, qy, qz, qw = cfToQuat(cf)
    return {f[1], f[2], f[3], qx, qy, qz, qw, f[6]}
end

-- Garante que um frame está no formato novo
local function normalizeFrame(f)
    if #f == 6 then return upgradeFrameLegacy(f) end
    return f
end

-- ─── Gravação ────────────────────────────────────────────────────────────────

local function gravarFrame()
    local agora = tick()
    if agora - ultimoFrameTime < RECORD_INTERVAL then return end
    ultimoFrameTime = agora

    local cf    = RootPart.CFrame
    local pos   = cf.Position
    local noAr  = estaNoAr()
    local pulou = noAr and not ultimoNoAr
    ultimoNoAr  = noAr

    local qx, qy, qz, qw = cfToQuat(cf)
    -- arredonda para compactar exportação
    local function r2(v) return math.round(v * 100) / 100 end
    local function r4(v) return math.round(v * 10000) / 10000 end

    frames[#frames + 1] = {
        r2(pos.X), r2(pos.Y), r2(pos.Z),
        r4(qx), r4(qy), r4(qz), r4(qw),
        pulou and 1 or 0,
    }
end

local function setNotice(text, color)
    if not noticeLbl then return end
    noticeLbl.Text       = text
    noticeLbl.TextColor3 = color
end

local function pararGravacao()
    if not gravando then return end
    gravando = false
    if conexaoGravacao then
        conexaoGravacao:Disconnect()
        conexaoGravacao = nil
    end
    activeSource = "recorded"
    setNotice(("Gravacao finalizada: %d frames (%.1fs)"):format(#frames, #frames / RECORD_FPS),
        Color3.fromRGB(118, 199, 255))
end

local function iniciarGravacao()
    if reproduzindo then return end
    refreshCharacter()
    restaurarRigDepoisPlayback()
    if Humanoid then Humanoid.PlatformStand = false end
    frames      = {}
    activeSource = "recorded"
    frameAtual  = 0
    gravando    = true
    ultimoNoAr  = false
    ultimoFrameTime = 0
    conexaoGravacao = RunService.Heartbeat:Connect(gravarFrame)
    setNotice("Gravando... (F para parar)", Color3.fromRGB(255, 100, 100))
end

-- ─── Reprodução ──────────────────────────────────────────────────────────────

local function aplicarFrameData(frame)
    local f = normalizeFrame(frame)
    Character:PivotTo(cfFromPosQuat(f[1], f[2], f[3], f[4], f[5], f[6], f[7]))
end

local function pararReproducao(finalNotice, finalColor)
    if conexaoReproducao then
        conexaoReproducao:Disconnect()
        conexaoReproducao = nil
    end
    reproduzindo = false
    pausado      = false
    frameAtual   = 0
    tempoPausadoAcumulado = 0
    tempoInicioPausa = 0
    restaurarRigDepoisPlayback()
    setNotice(finalNotice or "Reproducao parada.", finalColor or Color3.fromRGB(183, 194, 218))
end

local function iniciarReproducao()
    if gravando then pararGravacao() end

    local path, origem = getActivePath()
    local ok, msg = validarPath(path)
    if not ok then
        setNotice("ERRO: " .. msg, Color3.fromRGB(255, 120, 100))
        return
    end

    refreshCharacter()
    prepararRigParaPlayback()

    local total     = #path.f
    local fps       = path.fps
    local velocidade = getPlaybackSpeed()

    reproduzindo = true
    pausado      = false
    frameAtual   = 1
    tempoInicioReproducao = tick()
    tempoPausadoAcumulado = 0
    tempoInicioPausa = 0

    aplicarFrameData(path.f[1])
    task.wait(0.06)

    setNotice(("Reproduzindo [%s] em %.2fx"):format(origem, velocidade), Color3.fromRGB(120, 233, 159))

    conexaoReproducao = RunService.Heartbeat:Connect(function()
        if not reproduzindo or pausado then return end

        local tempo      = (tick() - tempoInicioReproducao - tempoPausadoAcumulado) * velocidade
        local frameIdeal = tempo * fps + 1

        if frameIdeal >= total then
            aplicarFrameData(path.f[total])
            frameAtual = total
            if loopAtivo then
                tempoInicioReproducao = tick()
                tempoPausadoAcumulado = 0
                frameAtual = 1
                aplicarFrameData(path.f[1])
                return
            end
            pararReproducao("Reproducao concluida.", Color3.fromRGB(120, 233, 159))
            return
        end

        local iA = math.clamp(math.floor(frameIdeal), 1, total)
        local iB = math.clamp(iA + 1, 1, total)
        local alpha = frameIdeal - iA

        local fA = normalizeFrame(path.f[iA])
        local fB = normalizeFrame(path.f[iB])

        -- Interpolação de posição (linear é suficiente para pos)
        local px = fA[1] + (fB[1] - fA[1]) * alpha
        local py = fA[2] + (fB[2] - fA[2]) * alpha
        local pz = fA[3] + (fB[3] - fA[3]) * alpha

        -- SLERP para rotação suave
        local qx, qy, qz, qw = slerpQuat(fA[4], fA[5], fA[6], fA[7], fB[4], fB[5], fB[6], fB[7], alpha)

        Character:PivotTo(cfFromPosQuat(px, py, pz, qx, qy, qz, qw))

        local novoFrame = math.floor(frameIdeal)
        if novoFrame ~= frameAtual then
            frameAtual = novoFrame
            local fd = path.f[frameAtual]
            if fd then
                local fnorm = normalizeFrame(fd)
                if fnorm[8] == 1 then
                    Humanoid.Jump = true
                    task.delay(0.05, function()
                        if Humanoid then Humanoid.Jump = false end
                    end)
                end
            end
        end
    end)
end

local function alternarPausa()
    if not reproduzindo then return end
    pausado = not pausado
    if pausado then
        tempoInicioPausa = tick()
        setNotice("Pausado. (H para retomar)", Color3.fromRGB(255, 214, 120))
    else
        tempoPausadoAcumulado = tempoPausadoAcumulado + (tick() - tempoInicioPausa)
        tempoInicioPausa = 0
        setNotice("Retomado.", Color3.fromRGB(120, 233, 159))
    end
end

local function limparTudo()
    pararGravacao()
    pararReproducao()
    frames       = {}
    importedPath = nil
    activeSource = "recorded"
    frameAtual   = 0
    if outputBox then outputBox.Text = "" end
    setNotice("Tudo limpo.", Color3.fromRGB(183, 194, 218))
end

local function ajustarVelocidade(delta)
    velocidadeIndex = math.clamp(velocidadeIndex + delta, 1, #PLAYBACK_SPEEDS)
    setNotice(("Velocidade: %.2fx"):format(getPlaybackSpeed()), Color3.fromRGB(183, 194, 218))
end

-- ─── Serialização / Parsing ──────────────────────────────────────────────────

local function serializarPath(path)
    local linhas = {EXPORT_START, ("fps=%d"):format(path.fps)}
    for _, frame in ipairs(path.f) do
        local f = normalizeFrame(frame)
        linhas[#linhas + 1] = string.format(
            "%.2f,%.2f,%.2f,%.4f,%.4f,%.4f,%.4f,%d",
            f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8]
        )
    end
    linhas[#linhas + 1] = EXPORT_END
    linhas[#linhas + 1] = ""
    linhas[#linhas + 1] = "-- Cole este bloco na caixa e clique em LOAD."
    return table.concat(linhas, "\n")
end

local function gerarCodigo()
    local path = (#frames > 0) and {fps = RECORD_FPS, f = frames} or importedPath or PATH_DATA
    local ok, msg = validarPath(path)
    if not ok then
        return "-- Nenhum path valido.\n-- Grave algo ou cole um bloco exportado."
    end
    return serializarPath(path)
end

local function parsePathText(text)
    if type(text) ~= "string" or text == "" then
        return nil, "A caixa esta vazia."
    end
    local startIndex = text:find(EXPORT_START, 1, true)
    local endIndex   = text:find(EXPORT_END,   1, true)
    if not startIndex or not endIndex or endIndex <= startIndex then
        return nil, "Bloco PATH_EXPORT nao encontrado."
    end
    local bloco = text:sub(startIndex + #EXPORT_START, endIndex - 1)
    local fps = tonumber(bloco:match("fps%s*=%s*([%d%.%-]+)"))
    if not fps or fps <= 0 then
        return nil, "FPS invalido no texto."
    end
    local path = {fps = fps, f = {}}
    for line in bloco:gmatch("[^\r\n]+") do
        if not line:match("^%s*fps%s*=") then
            local nums = {}
            for num in line:gmatch("%-?%d+%.?%d*") do
                nums[#nums + 1] = tonumber(num)
            end
            if #nums > 0 then
                if #nums == 6 then
                    -- frame legado — aceita e converte
                    path.f[#path.f + 1] = nums
                elseif #nums == 8 then
                    path.f[#path.f + 1] = nums
                else
                    return nil, ("Frame com %d numeros (esperado 6 ou 8)."):format(#nums)
                end
            end
        end
    end
    local ok, msg = validarPath(path)
    if not ok then return nil, msg end
    return path, "OK"
end

local function carregarDaCaixa()
    local path, msg = parsePathText(outputBox.Text)
    if not path then
        setNotice("ERRO: " .. msg, Color3.fromRGB(255, 120, 100))
        return
    end
    importedPath = path
    activeSource = "imported"
    frameAtual   = 0
    setNotice(("Carregado da caixa: %d frames (%.1fs)"):format(#path.f, #path.f / path.fps),
        Color3.fromRGB(118, 199, 255))
end

-- ─── UI ──────────────────────────────────────────────────────────────────────

local existingGui = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("MovementStudioGui")
if existingGui then existingGui:Destroy() end

local sg = Instance.new("ScreenGui")
sg.Name          = "MovementStudioGui"
sg.ResetOnSpawn  = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent        = LocalPlayer.PlayerGui

-- Cores do tema
local C = {
    BG       = Color3.fromRGB(11, 15, 24),
    BG2      = Color3.fromRGB(16, 22, 36),
    BG3      = Color3.fromRGB(8, 11, 18),
    BORDER   = Color3.fromRGB(40, 68, 110),
    TEXT     = Color3.fromRGB(215, 228, 252),
    MUTED    = Color3.fromRGB(108, 132, 172),
    RED      = Color3.fromRGB(180, 55, 68),
    BLUE     = Color3.fromRGB(50, 98, 188),
    GREEN    = Color3.fromRGB(38, 140, 104),
    AMBER    = Color3.fromRGB(148, 112, 30),
    PURPLE   = Color3.fromRGB(86, 64, 158),
    SLATE    = Color3.fromRGB(50, 64, 96),
    ACCENT   = Color3.fromRGB(72, 152, 255),
}

local function addCorner(parent, radius)
    local c = Instance.new("UICorner", parent)
    c.CornerRadius = UDim.new(0, radius or 12)
    return c
end

local function addStroke(parent, color, thickness)
    local s = Instance.new("UIStroke", parent)
    s.Color     = color or C.BORDER
    s.Thickness = thickness or 1
    return s
end

local function makeLbl(parent, props)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Font      = props.font or Enum.Font.Gotham
    lbl.TextSize  = props.size or 11
    lbl.TextColor3 = props.color or C.TEXT
    lbl.Text      = props.text or ""
    lbl.Size      = props.sz   or UDim2.new(1, 0, 0, 18)
    lbl.Position  = props.pos  or UDim2.new(0, 0, 0, 0)
    lbl.TextXAlignment = props.xa or Enum.TextXAlignment.Left
    lbl.TextWrapped = props.wrap or false
    lbl.Parent    = parent
    return lbl
end

local function pulse(button)
    local orig = button.Size
    local small = UDim2.new(orig.X.Scale, orig.X.Offset - 4, orig.Y.Scale, orig.Y.Offset - 4)
    local d = TweenService:Create(button, TweenInfo.new(0.06), {Size = small})
    local u = TweenService:Create(button, TweenInfo.new(0.09), {Size = orig})
    d:Play()
    d.Completed:Connect(function() u:Play() end)
end

local function makeBtn(parent, text, color, sz, pos, cb)
    local b = Instance.new("TextButton")
    b.Size             = sz
    b.Position         = pos
    b.BackgroundColor3 = color
    b.BorderSizePixel  = 0
    b.Text             = text
    b.TextColor3       = Color3.fromRGB(240, 245, 255)
    b.Font             = Enum.Font.GothamBold
    b.TextSize         = 10
    b.AutoButtonColor  = false
    b.Parent           = parent
    addCorner(b, 8)
    addStroke(b, color:Lerp(Color3.new(1,1,1), 0.18))
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.1), {BackgroundColor3 = color:Lerp(Color3.new(1,1,1), 0.1)}):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.1), {BackgroundColor3 = color}):Play()
    end)
    b.MouseButton1Click:Connect(function()
        pulse(b)
        cb()
    end)
    return b
end

-- ─── Painel principal (menor: 320×270) ───────────────────────────────────────

local root = Instance.new("Frame")
root.Size            = UDim2.new(0, 320, 0, 268)
root.Position        = UDim2.new(0, 12, 0.5, -134)
root.BackgroundColor3 = C.BG
root.BorderSizePixel = 0
root.Active          = true
root.Draggable       = true
root.Parent          = sg
addCorner(root, 16)
addStroke(root, C.BORDER)

-- Cabeçalho
local hdr = Instance.new("Frame")
hdr.Size             = UDim2.new(1, 0, 0, 48)
hdr.BackgroundColor3 = C.BG3
hdr.BorderSizePixel  = 0
hdr.Parent           = root
addCorner(hdr, 16)
-- tampa o canto redondo de baixo do header
local hdrFix = Instance.new("Frame")
hdrFix.Size             = UDim2.new(1, 0, 0, 16)
hdrFix.Position         = UDim2.new(0, 0, 1, -16)
hdrFix.BackgroundColor3 = C.BG3
hdrFix.BorderSizePixel  = 0
hdrFix.Parent           = hdr

-- Ponto de status (LED)
statusDot = Instance.new("Frame")
statusDot.Size             = UDim2.new(0, 8, 0, 8)
statusDot.Position         = UDim2.new(0, 14, 0, 12)
statusDot.BackgroundColor3 = C.MUTED
statusDot.BorderSizePixel  = 0
statusDot.Parent           = hdr
addCorner(statusDot, 100)

statusLbl = makeLbl(hdr, {
    text  = "MOVEMENT STUDIO",
    font  = Enum.Font.GothamBold,
    size  = 13,
    color = C.TEXT,
    sz    = UDim2.new(1, -40, 0, 20),
    pos   = UDim2.new(0, 28, 0, 6),
})

detailsLbl = makeLbl(hdr, {
    text  = "0 frames | 0.0s | fonte: nenhuma",
    size  = 9,
    color = C.MUTED,
    sz    = UDim2.new(1, -28, 0, 14),
    pos   = UDim2.new(0, 14, 0, 30),
})

-- Chips de estado
local function makeChip(parent, text, x)
    local chip = Instance.new("TextLabel")
    chip.Size             = UDim2.new(0, 84, 0, 18)
    chip.Position         = UDim2.new(0, x, 0, 54)
    chip.BackgroundColor3 = C.BG2
    chip.BorderSizePixel  = 0
    chip.Text             = text
    chip.TextColor3       = C.TEXT
    chip.Font             = Enum.Font.GothamMedium
    chip.TextSize         = 9
    chip.Parent           = parent
    addCorner(chip, 100)
    return chip
end

sourceChip = makeChip(root, "GRAVACAO", 10)
speedChip  = makeChip(root, "1.00x", 100)
loopChip   = makeChip(root, "LOOP OFF", 190)

-- Barra de progresso
local progressBg = Instance.new("Frame")
progressBg.Size             = UDim2.new(1, -20, 0, 4)
progressBg.Position         = UDim2.new(0, 10, 0, 78)
progressBg.BackgroundColor3 = C.BG3
progressBg.BorderSizePixel  = 0
progressBg.Parent           = root
addCorner(progressBg, 100)

progressFill = Instance.new("Frame")
progressFill.Size             = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = C.ACCENT
progressFill.BorderSizePixel  = 0
progressFill.Parent           = progressBg
addCorner(progressFill, 100)

progressLbl = makeLbl(root, {
    text  = "0 / 0",
    size  = 8,
    color = C.MUTED,
    sz    = UDim2.new(1, -20, 0, 12),
    pos   = UDim2.new(0, 10, 0, 84),
    xa    = Enum.TextXAlignment.Right,
})

-- Bloco de controles primários (REC, PLAY, PAUSE, LOOP)
local row1 = Instance.new("Frame")
row1.Size             = UDim2.new(1, -20, 0, 30)
row1.Position         = UDim2.new(0, 10, 0, 100)
row1.BackgroundTransparency = 1
row1.Parent           = root

local BW = 68  -- largura botão
local GAP = 4

recBtn   = makeBtn(row1, "REC",   C.RED,    UDim2.new(0, BW, 0, 30), UDim2.new(0, 0*(BW+GAP), 0, 0), function()
    if gravando then pararGravacao() else iniciarGravacao() end
end)
playBtn  = makeBtn(row1, "PLAY",  C.BLUE,   UDim2.new(0, BW, 0, 30), UDim2.new(0, 1*(BW+GAP), 0, 0), function()
    if reproduzindo then pararReproducao() else iniciarReproducao() end
end)
pauseBtn = makeBtn(row1, "PAUSE", C.AMBER,  UDim2.new(0, BW, 0, 30), UDim2.new(0, 2*(BW+GAP), 0, 0), alternarPausa)
loopBtn  = makeBtn(row1, "LOOP",  C.PURPLE, UDim2.new(0, BW, 0, 30), UDim2.new(0, 3*(BW+GAP), 0, 0), function()
    loopAtivo = not loopAtivo
    setNotice("Loop " .. (loopAtivo and "ativado." or "desativado."), C.MUTED)
end)

-- Bloco de controles secundários (LOAD, EXPORT, CLEAR, VEL-, VEL+)
local row2 = Instance.new("Frame")
row2.Size             = UDim2.new(1, -20, 0, 30)
row2.Position         = UDim2.new(0, 10, 0, 136)
row2.BackgroundTransparency = 1
row2.Parent           = root

local SW = 54  -- largura botão secundário
loadBtn     = makeBtn(row2, "LOAD",   C.GREEN, UDim2.new(0, SW, 0, 30), UDim2.new(0, 0*(SW+GAP), 0, 0), carregarDaCaixa)
exportBtn   = makeBtn(row2, "EXPORT", C.GREEN, UDim2.new(0, SW, 0, 30), UDim2.new(0, 1*(SW+GAP), 0, 0), function()
    outputBox.Text = gerarCodigo()
    setNotice("Codigo gerado na caixa.", C.ACCENT)
end)
clearBtn    = makeBtn(row2, "CLEAR",  C.SLATE, UDim2.new(0, SW, 0, 30), UDim2.new(0, 2*(SW+GAP), 0, 0), limparTudo)
speedDownBtn = makeBtn(row2, "VEL-",  C.SLATE, UDim2.new(0, SW, 0, 30), UDim2.new(0, 3*(SW+GAP), 0, 0), function() ajustarVelocidade(-1) end)
speedUpBtn  = makeBtn(row2, "VEL+",  C.SLATE, UDim2.new(0, SW, 0, 30), UDim2.new(0, 4*(SW+GAP), 0, 0), function() ajustarVelocidade(1) end)

-- Seleção de fonte
local srcRow = Instance.new("Frame")
srcRow.Size             = UDim2.new(1, -20, 0, 26)
srcRow.Position         = UDim2.new(0, 10, 0, 172)
srcRow.BackgroundTransparency = 1
srcRow.Parent           = root

local srcTitle = makeLbl(srcRow, {
    text  = "FONTE:",
    size  = 9,
    color = C.MUTED,
    font  = Enum.Font.GothamBold,
    sz    = UDim2.new(0, 50, 1, 0),
    pos   = UDim2.new(0, 0, 0, 0),
})

local srcGravBtn = makeBtn(srcRow, "GRAVACAO", C.SLATE, UDim2.new(0, 90, 0, 22), UDim2.new(0, 52, 0, 2), function()
    activeSource = "recorded"
    setNotice("Fonte: gravacao.", C.ACCENT)
end)
local srcCaixaBtn = makeBtn(srcRow, "CAIXA", C.SLATE, UDim2.new(0, 70, 0, 22), UDim2.new(0, 148, 0, 2), function()
    activeSource = "imported"
    setNotice("Fonte: caixa.", C.ACCENT)
end)

-- Mensagem de status
noticeLbl = makeLbl(root, {
    text  = "Pronto. F=Gravar G=Play H=Pause J=Limpar K=Export L=Loop",
    size  = 8,
    color = C.MUTED,
    sz    = UDim2.new(1, -20, 0, 28),
    pos   = UDim2.new(0, 10, 0, 202),
    wrap  = true,
})

-- ─── Painel de código (compacto, ao lado) ────────────────────────────────────

local codePanel = Instance.new("Frame")
codePanel.Size             = UDim2.new(0, 300, 0, 210)
codePanel.Position         = UDim2.new(0, 342, 0.5, -105)
codePanel.BackgroundColor3 = C.BG
codePanel.BorderSizePixel  = 0
codePanel.Active           = true
codePanel.Draggable        = true
codePanel.Parent           = sg
addCorner(codePanel, 16)
addStroke(codePanel, C.BORDER)

makeLbl(codePanel, {
    text  = "CAIXA DE CODIGO",
    font  = Enum.Font.GothamBold,
    size  = 11,
    color = C.TEXT,
    sz    = UDim2.new(1, -24, 0, 20),
    pos   = UDim2.new(0, 14, 0, 10),
})

makeLbl(codePanel, {
    text  = "Cole o bloco exportado aqui, depois clique LOAD.",
    size  = 9,
    color = C.MUTED,
    sz    = UDim2.new(1, -24, 0, 14),
    pos   = UDim2.new(0, 14, 0, 32),
    wrap  = true,
})

local outputFrame = Instance.new("Frame")
outputFrame.Size             = UDim2.new(1, -20, 0, 152)
outputFrame.Position         = UDim2.new(0, 10, 0, 50)
outputFrame.BackgroundColor3 = C.BG3
outputFrame.BorderSizePixel  = 0
outputFrame.Parent           = codePanel
addCorner(outputFrame, 10)
addStroke(outputFrame, C.BORDER)

outputBox = Instance.new("TextBox")
outputBox.Size             = UDim2.new(1, -14, 1, -14)
outputBox.Position         = UDim2.new(0, 7, 0, 7)
outputBox.BackgroundTransparency = 1
outputBox.ClearTextOnFocus = false
outputBox.MultiLine        = true
outputBox.TextEditable     = true
outputBox.TextWrapped      = false
outputBox.TextXAlignment   = Enum.TextXAlignment.Left
outputBox.TextYAlignment   = Enum.TextYAlignment.Top
outputBox.Text             = ""
outputBox.TextColor3       = Color3.fromRGB(140, 220, 170)
outputBox.Font             = Enum.Font.Code
outputBox.TextSize         = 9
outputBox.Parent           = outputFrame

-- ─── Atualização de UI ───────────────────────────────────────────────────────

local dotPulseTime = 0

local function updateUi()
    local path, origem = getActivePath()
    local totalFrames  = (path and path.f) and #path.f or 0
    local fps          = (path and path.fps) or RECORD_FPS

    -- Estado / label
    if gravando then
        statusLbl.Text       = "GRAVANDO"
        statusLbl.TextColor3 = Color3.fromRGB(255, 100, 100)
        recBtn.Text          = "PARAR"
        -- pisca o LED
        dotPulseTime = dotPulseTime + 0.016
        local alpha = (math.sin(dotPulseTime * 6) + 1) / 2
        statusDot.BackgroundColor3 = Color3.fromRGB(255, 100, 100):Lerp(C.BG3, 1 - alpha)
    elseif reproduzindo and pausado then
        statusLbl.Text       = "PAUSADO"
        statusLbl.TextColor3 = Color3.fromRGB(255, 214, 120)
        statusDot.BackgroundColor3 = Color3.fromRGB(255, 214, 120)
        recBtn.Text          = "REC"
    elseif reproduzindo then
        statusLbl.Text       = "REPRODUZINDO"
        statusLbl.TextColor3 = Color3.fromRGB(120, 233, 159)
        statusDot.BackgroundColor3 = Color3.fromRGB(120, 233, 159)
        recBtn.Text          = "REC"
    else
        statusLbl.Text       = "PRONTO"
        statusLbl.TextColor3 = C.MUTED
        statusDot.BackgroundColor3 = C.MUTED
        recBtn.Text          = "REC"
        dotPulseTime         = 0
    end

    playBtn.Text  = reproduzindo and "STOP" or "PLAY"
    pauseBtn.Text = pausado and "CONT." or "PAUSE"
    loopBtn.Text  = loopAtivo and "LOOP ON" or "LOOP"

    detailsLbl.Text = string.format(
        "%d frames | %.1fs | %s",
        totalFrames,
        totalFrames > 0 and (totalFrames / fps) or 0,
        origem or "nenhuma"
    )

    sourceChip.Text = activeSource == "imported" and "CAIXA" or "GRAVACAO"
    sourceChip.BackgroundColor3 = activeSource == "imported"
        and Color3.fromRGB(22, 58, 58) or C.BG2

    speedChip.Text = ("%.2fx"):format(getPlaybackSpeed())
    loopChip.Text  = loopAtivo and "LOOP ON" or "LOOP OFF"
    loopChip.BackgroundColor3 = loopAtivo and Color3.fromRGB(50, 38, 90) or C.BG2

    progressLbl.Text = string.format("%d / %d", frameAtual, totalFrames)
    local pct = totalFrames > 0 and (frameAtual / totalFrames) or 0
    progressFill.Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0)
end

RunService.Heartbeat:Connect(updateUi)

-- ─── Atalhos de teclado ──────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    local k = inp.KeyCode
    if     k == Enum.KeyCode.F then
        if gravando then pararGravacao() else iniciarGravacao() end
    elseif k == Enum.KeyCode.G then
        if reproduzindo then pararReproducao() else iniciarReproducao() end
    elseif k == Enum.KeyCode.H then
        alternarPausa()
    elseif k == Enum.KeyCode.J then
        limparTudo()
    elseif k == Enum.KeyCode.K then
        outputBox.Text = gerarCodigo()
        setNotice("Codigo gerado na caixa.", C.ACCENT)
    elseif k == Enum.KeyCode.L then
        loopAtivo = not loopAtivo
    elseif k == Enum.KeyCode.Equals or k == Enum.KeyCode.KeypadPlus then
        ajustarVelocidade(1)
    elseif k == Enum.KeyCode.Minus or k == Enum.KeyCode.KeypadMinus then
        ajustarVelocidade(-1)
    end
end)

-- ─── Inicialização ───────────────────────────────────────────────────────────

if PATH_DATA then
    local ok, msg = validarPath(PATH_DATA)
    if ok then
        importedPath = PATH_DATA
        activeSource = "imported"
        setNotice("PATH_DATA inicial carregado.", C.ACCENT)
    else
        setNotice("PATH_DATA invalido: " .. msg, Color3.fromRGB(255, 120, 100))
    end
else
    setNotice("Pronto. F=Gravar G=Play H=Pause J=Limpar K=Export L=Loop", C.MUTED)
end

print("[MOVEMENT STUDIO v2] OK — F=Gravar | G=Play | H=Pause | J=Limpar | K=Export | L=Loop | +/-=Velocidade")
