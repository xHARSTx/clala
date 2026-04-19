-- TurtleSpy V3.0 Complete - Remote Spy Browser
-- Versão completa SEM necessidade de hooks
-- Baseado no TurtleSpy original

local settings = {
    Keybind = Enum.KeyCode.P
}

-- Serviços
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- Limpar versão anterior
pcall(function()
    if CoreGui:FindFirstChild("TurtleSpyGUI") then
        CoreGui:FindFirstChild("TurtleSpyGUI"):Destroy()
    end
end)

-- Verificar suporte do executor
local hasSetClipboard = setclipboard ~= nil
local hasDecompile = decompile ~= nil

-- Cores do tema
local colors = {
    headerColor = Color3.fromRGB(0, 168, 255),
    headerShading = Color3.fromRGB(0, 151, 230),
    headerText = Color3.fromRGB(47, 54, 64),
    mainBg = Color3.fromRGB(47, 54, 64),
    infoBg = Color3.fromRGB(47, 54, 64),
    scrollBar = Color3.fromRGB(127, 143, 166),
    buttonBg = Color3.fromRGB(53, 59, 72),
    buttonBorder = Color3.fromRGB(113, 128, 147),
    buttonText = Color3.fromRGB(220, 221, 225),
    codeBg = Color3.fromRGB(35, 40, 48),
    codeText = Color3.fromRGB(220, 221, 225),
    codeComment = Color3.fromRGB(108, 108, 108),
    green = Color3.fromRGB(46, 204, 113),
    red = Color3.fromRGB(231, 76, 60),
    orange = Color3.fromRGB(230, 126, 34)
}

-- Dados
local remoteList = {}
local selectedRemote = nil
local selectedRemoteType = nil

-- Função para obter caminho completo
local function GetFullPath(instance)
    if not instance then return "nil" end
    if instance == game then return "game" end
    if instance == workspace then return "workspace" end
    
    local path = {}
    local current = instance
    
    while current and current ~= game do
        if current == workspace then
            table.insert(path, 1, "workspace")
            break
        end
        
        local name = current.Name
        
        -- Verificar se precisa de aspas
        if name:match("^[%a_][%w_]*$") and not name:match("^%d") then
            table.insert(path, 1, "." .. name)
        else
            -- Nome com caracteres especiais
            name = name:gsub('"', '\\"'):gsub('\\', '\\\\')
            table.insert(path, 1, '["' .. name .. '"]')
        end
        
        current = current.Parent
    end
    
    if #path == 0 then return "game" end
    
    local result = "game" .. table.concat(path)
    
    -- Tentar usar GetService
    local success, service = pcall(function()
        return game:GetService(instance.ClassName)
    end)
    
    if success and service == instance then
        return 'game:GetService("' .. instance.ClassName .. '")'
    end
    
    return result
end

-- Criar GUI
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "TurtleSpyGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    ScreenGui.Parent = CoreGui
end)

if not ScreenGui.Parent then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

-- Frame Principal
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 800, 0, 500)
MainFrame.Position = UDim2.new(0.5, -400, 0.5, -250)
MainFrame.BackgroundColor3 = colors.mainBg
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

-- Header
local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 35)
Header.BackgroundColor3 = colors.headerColor
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 10)
HeaderCorner.Parent = Header

local HeaderCover = Instance.new("Frame")
HeaderCover.Size = UDim2.new(1, 0, 0, 12)
HeaderCover.Position = UDim2.new(0, 0, 1, -12)
HeaderCover.BackgroundColor3 = colors.headerColor
HeaderCover.BorderSizePixel = 0
HeaderCover.Parent = Header

local HeaderShading = Instance.new("Frame")
HeaderShading.Size = UDim2.new(1, 0, 0, 8)
HeaderShading.Position = UDim2.new(0, 0, 1, 0)
HeaderShading.BackgroundColor3 = colors.headerShading
HeaderShading.BorderSizePixel = 0
HeaderShading.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -100, 1, 0)
Title.Position = UDim2.new(0, 10, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🐢 TurtleSpy V3.0 - Remote Browser"
Title.TextColor3 = colors.headerText
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 17
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

-- Botão Fechar
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -35, 0, 2.5)
CloseBtn.BackgroundColor3 = colors.red
CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.SourceSansBold
CloseBtn.TextSize = 16
CloseBtn.Parent = Header

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui.Enabled = false
end)

-- Botão Minimizar
local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 30, 0, 30)
MinBtn.Position = UDim2.new(1, -70, 0, 2.5)
MinBtn.BackgroundColor3 = colors.buttonBg
MinBtn.BorderSizePixel = 0
MinBtn.Text = "_"
MinBtn.TextColor3 = colors.headerText
MinBtn.Font = Enum.Font.SourceSansBold
MinBtn.TextSize = 18
MinBtn.Parent = Header

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 6)
MinCorner.Parent = MinBtn

local minimized = false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        MainFrame.Size = UDim2.new(0, 800, 0, 35)
    else
        MainFrame.Size = UDim2.new(0, 800, 0, 500)
    end
end)

-- Container Principal
local Container = Instance.new("Frame")
Container.Size = UDim2.new(1, -20, 1, -50)
Container.Position = UDim2.new(0, 10, 0, 45)
Container.BackgroundTransparency = 1
Container.Parent = MainFrame

-- ========== PAINEL ESQUERDO - LISTA DE REMOTES ==========
local LeftPanel = Instance.new("Frame")
LeftPanel.Name = "LeftPanel"
LeftPanel.Size = UDim2.new(0.35, -5, 1, 0)
LeftPanel.BackgroundColor3 = colors.infoBg
LeftPanel.BorderSizePixel = 0
LeftPanel.Parent = Container

local LeftCorner = Instance.new("UICorner")
LeftCorner.CornerRadius = UDim.new(0, 8)
LeftCorner.Parent = LeftPanel

local LeftTitle = Instance.new("TextLabel")
LeftTitle.Size = UDim2.new(1, -10, 0, 25)
LeftTitle.Position = UDim2.new(0, 5, 0, 5)
LeftTitle.BackgroundTransparency = 1
LeftTitle.Text = "📡 Remotes Encontrados (0)"
LeftTitle.TextColor3 = colors.buttonText
LeftTitle.Font = Enum.Font.SourceSansBold
LeftTitle.TextSize = 14
LeftTitle.TextXAlignment = Enum.TextXAlignment.Left
LeftTitle.Parent = LeftPanel

-- Barra de pesquisa
local SearchBox = Instance.new("TextBox")
SearchBox.Size = UDim2.new(1, -10, 0, 30)
SearchBox.Position = UDim2.new(0, 5, 0, 35)
SearchBox.BackgroundColor3 = colors.codeBg
SearchBox.BorderSizePixel = 0
SearchBox.Text = ""
SearchBox.PlaceholderText = "🔍 Pesquisar remote..."
SearchBox.TextColor3 = colors.codeText
SearchBox.PlaceholderColor3 = colors.scrollBar
SearchBox.Font = Enum.Font.SourceSans
SearchBox.TextSize = 13
SearchBox.TextXAlignment = Enum.TextXAlignment.Left
SearchBox.Parent = LeftPanel

local SearchCorner = Instance.new("UICorner")
SearchCorner.CornerRadius = UDim.new(0, 6)
SearchCorner.Parent = SearchBox

-- ScrollFrame para lista
local RemoteScroll = Instance.new("ScrollingFrame")
RemoteScroll.Size = UDim2.new(1, -10, 1, -110)
RemoteScroll.Position = UDim2.new(0, 5, 0, 70)
RemoteScroll.BackgroundTransparency = 1
RemoteScroll.BorderSizePixel = 0
RemoteScroll.ScrollBarThickness = 6
RemoteScroll.ScrollBarImageColor3 = colors.scrollBar
RemoteScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
RemoteScroll.Parent = LeftPanel

local RemoteLayout = Instance.new("UIListLayout")
RemoteLayout.Padding = UDim.new(0, 3)
RemoteLayout.SortOrder = Enum.SortOrder.Name
RemoteLayout.Parent = RemoteScroll

RemoteLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    RemoteScroll.CanvasSize = UDim2.new(0, 0, 0, RemoteLayout.AbsoluteContentSize.Y + 5)
end)

-- Botão Escanear
local ScanBtn = Instance.new("TextButton")
ScanBtn.Size = UDim2.new(1, -10, 0, 30)
ScanBtn.Position = UDim2.new(0, 5, 1, -35)
ScanBtn.BackgroundColor3 = colors.green
ScanBtn.BorderSizePixel = 0
ScanBtn.Text = "🔄 Escanear Remotes"
ScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanBtn.Font = Enum.Font.SourceSansBold
ScanBtn.TextSize = 13
ScanBtn.Parent = LeftPanel

local ScanCorner = Instance.new("UICorner")
ScanCorner.CornerRadius = UDim.new(0, 6)
ScanCorner.Parent = ScanBtn

-- ========== PAINEL DIREITO - INFORMAÇÕES ==========
local RightPanel = Instance.new("Frame")
RightPanel.Name = "RightPanel"
RightPanel.Size = UDim2.new(0.65, -5, 1, 0)
RightPanel.Position = UDim2.new(0.35, 5, 0, 0)
RightPanel.BackgroundColor3 = colors.infoBg
RightPanel.BorderSizePixel = 0
RightPanel.Parent = Container

local RightCorner = Instance.new("UICorner")
RightCorner.CornerRadius = UDim.new(0, 8)
RightCorner.Parent = RightPanel

local RightTitle = Instance.new("TextLabel")
RightTitle.Size = UDim2.new(1, -10, 0, 25)
RightTitle.Position = UDim2.new(0, 5, 0, 5)
RightTitle.BackgroundTransparency = 1
RightTitle.Text = "📝 Informações do Remote"
RightTitle.TextColor3 = colors.buttonText
RightTitle.Font = Enum.Font.SourceSansBold
RightTitle.TextSize = 14
RightTitle.TextXAlignment = Enum.TextXAlignment.Left
RightTitle.Parent = RightPanel

-- Caixa de código
local CodeFrame = Instance.new("ScrollingFrame")
CodeFrame.Size = UDim2.new(1, -10, 0.5, -5)
CodeFrame.Position = UDim2.new(0, 5, 0, 35)
CodeFrame.BackgroundColor3 = colors.codeBg
CodeFrame.BorderSizePixel = 0
CodeFrame.ScrollBarThickness = 6
CodeFrame.ScrollBarImageColor3 = colors.scrollBar
CodeFrame.CanvasSize = UDim2.new(2, 0, 0, 100)
CodeFrame.Parent = RightPanel

local CodeCorner = Instance.new("UICorner")
CodeCorner.CornerRadius = UDim.new(0, 6)
CodeCorner.Parent = CodeFrame

local CodeComment = Instance.new("TextLabel")
CodeComment.Size = UDim2.new(0, 10000, 0, 20)
CodeComment.Position = UDim2.new(0, 5, 0, 5)
CodeComment.BackgroundTransparency = 1
CodeComment.Text = "-- TurtleSpy V3.0 - Selecione um remote da lista"
CodeComment.TextColor3 = colors.codeComment
CodeComment.Font = Enum.Font.Code
CodeComment.TextSize = 13
CodeComment.TextXAlignment = Enum.TextXAlignment.Left
CodeComment.Parent = CodeFrame

local CodeText = Instance.new("TextLabel")
CodeText.Size = UDim2.new(0, 10000, 0, 20)
CodeText.Position = UDim2.new(0, 5, 0, 30)
CodeText.BackgroundTransparency = 1
CodeText.Text = ""
CodeText.TextColor3 = colors.codeText
CodeText.Font = Enum.Font.Code
CodeText.TextSize = 13
CodeText.TextXAlignment = Enum.TextXAlignment.Left
CodeText.Parent = CodeFrame

-- Container de botões
local ButtonScroll = Instance.new("ScrollingFrame")
ButtonScroll.Size = UDim2.new(1, -10, 0.5, -40)
ButtonScroll.Position = UDim2.new(0, 5, 0.5, 5)
ButtonScroll.BackgroundTransparency = 1
ButtonScroll.BorderSizePixel = 0
ButtonScroll.ScrollBarThickness = 6
ButtonScroll.ScrollBarImageColor3 = colors.scrollBar
ButtonScroll.CanvasSize = UDim2.new(0, 0, 0, 400)
ButtonScroll.Parent = RightPanel

local ButtonLayout = Instance.new("UIListLayout")
ButtonLayout.Padding = UDim.new(0, 5)
ButtonLayout.Parent = ButtonScroll

ButtonLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    ButtonScroll.CanvasSize = UDim2.new(0, 0, 0, ButtonLayout.AbsoluteContentSize.Y + 5)
end)

-- Função para criar botões
local function CreateButton(text, parent)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 30)
    btn.BackgroundColor3 = colors.buttonBg
    btn.BorderColor3 = colors.buttonBorder
    btn.BorderSizePixel = 1
    btn.Text = text
    btn.TextColor3 = colors.buttonText
    btn.Font = Enum.Font.SourceSans
    btn.TextSize = 13
    btn.Parent = parent or ButtonScroll
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn
    
    return btn
end

-- Criar botões
local CopyPathBtn = CreateButton("📋 Copiar Caminho")
local CopyFireBtn = CreateButton("🚀 Copiar com :FireServer()")
local CopyInvokeBtn = CreateButton("⚡ Copiar com :InvokeServer()")
local CopyScriptBtn = CreateButton("📜 Copiar Caminho do Script")
local DecompileBtn = CreateButton("🔓 Decompile Script")
local TestFireBtn = CreateButton("▶️ Testar FireServer()")
local TestInvokeBtn = CreateButton("▶️ Testar InvokeServer()")

-- Info do executor
local InfoText = Instance.new("TextLabel")
InfoText.Size = UDim2.new(1, 0, 0, 20)
InfoText.BackgroundTransparency = 1
InfoText.Text = string.format(
    "Executor: setclipboard=%s | decompile=%s",
    hasSetClipboard and "✅" or "❌",
    hasDecompile and "✅" or "❌"
)
InfoText.TextColor3 = colors.codeComment
InfoText.Font = Enum.Font.Code
InfoText.TextSize = 11
InfoText.TextXAlignment = Enum.TextXAlignment.Left
InfoText.Parent = ButtonScroll

-- Função para criar item da lista
local function CreateRemoteItem(remote)
    local isEvent = remote:IsA("RemoteEvent")
    
    local item = Instance.new("TextButton")
    item.Name = remote.Name
    item.Size = UDim2.new(1, 0, 0, 30)
    item.BackgroundColor3 = colors.buttonBg
    item.BorderColor3 = colors.buttonBorder
    item.BorderSizePixel = 1
    item.Text = ""
    item.AutoButtonColor = false
    item.Parent = RemoteScroll
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = item
    
    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(0, 25, 1, 0)
    icon.BackgroundTransparency = 1
    icon.Text = isEvent and "📡" or "⚡"
    icon.TextColor3 = colors.buttonText
    icon.TextSize = 14
    icon.Parent = item
    
    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(1, -30, 1, 0)
    name.Position = UDim2.new(0, 25, 0, 0)
    name.BackgroundTransparency = 1
    name.Text = remote.Name
    name.TextColor3 = colors.buttonText
    name.Font = Enum.Font.SourceSans
    name.TextSize = 12
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.TextTruncate = Enum.TextTruncate.AtEnd
    name.Parent = item
    
    item.MouseButton1Click:Connect(function()
        selectedRemote = remote
        selectedRemoteType = isEvent and "RemoteEvent" or "RemoteFunction"
        
        -- Atualizar visual
        for _, child in ipairs(RemoteScroll:GetChildren()) do
            if child:IsA("TextButton") then
                child.BackgroundColor3 = colors.buttonBg
            end
        end
        item.BackgroundColor3 = Color3.fromRGB(70, 80, 95)
        
        -- Atualizar código
        local path = GetFullPath(remote)
        local parent = remote.Parent and GetFullPath(remote.Parent) or "nil"
        
        CodeComment.Text = string.format(
            "-- Nome: %s\n-- Tipo: %s\n-- Parent: %s",
            remote.Name,
            selectedRemoteType,
            parent
        )
        
        CodeText.Text = path
        
        RightTitle.Text = "📝 Info: " .. remote.Name
    end)
    
    return item
end

-- Função para escanear remotes
local function ScanRemotes(searchTerm)
    -- Limpar lista
    for _, child in ipairs(RemoteScroll:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
    
    remoteList = {}
    local count = 0
    
    -- Escanear game
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            if not searchTerm or searchTerm == "" or obj.Name:lower():find(searchTerm:lower(), 1, true) then
                table.insert(remoteList, obj)
                CreateRemoteItem(obj)
                count = count + 1
            end
        end
    end
    
    LeftTitle.Text = string.format("📡 Remotes Encontrados (%d)", count)
    
    ScanBtn.Text = "✅ " .. count .. " remotes encontrados"
    task.wait(1.5)
    ScanBtn.Text = "🔄 Escanear Remotes"
end

-- Função para feedback visual
local function ButtonFeedback(button, text, color, duration)
    local originalText = button.Text
    local originalColor = button.BackgroundColor3
    
    button.Text = text
    button.BackgroundColor3 = color or colors.green
    
    task.wait(duration or 1.5)
    
    button.Text = originalText
    button.BackgroundColor3 = originalColor
end

-- Eventos dos botões
ScanBtn.MouseButton1Click:Connect(function()
    ScanRemotes(SearchBox.Text)
end)

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    if SearchBox.Text ~= "" then
        ScanRemotes(SearchBox.Text)
    end
end)

CopyPathBtn.MouseButton1Click:Connect(function()
    if not selectedRemote then
        ButtonFeedback(CopyPathBtn, "❌ Selecione um remote", colors.red)
        return
    end
    
    if hasSetClipboard then
        setclipboard(GetFullPath(selectedRemote))
        ButtonFeedback(CopyPathBtn, "✅ Caminho copiado!")
    else
        ButtonFeedback(CopyPathBtn, "❌ setclipboard não suportado", colors.red)
    end
end)

CopyFireBtn.MouseButton1Click:Connect(function()
    if not selectedRemote then
        ButtonFeedback(CopyFireBtn, "❌ Selecione um remote", colors.red)
        return
    end
    
    if hasSetClipboard then
        local code = GetFullPath(selectedRemote) .. ":FireServer()"
        setclipboard(code)
        ButtonFeedback(CopyFireBtn, "✅ Código copiado!")
    else
        ButtonFeedback(CopyFireBtn, "❌ setclipboard não suportado", colors.red)
    end
end)

CopyInvokeBtn.MouseButton1Click:Connect(function()
    if not selectedRemote then
        ButtonFeedback(CopyInvokeBtn, "❌ Selecione um remote", colors.red)
        return
    end
    
    if hasSetClipboard then
        local code = GetFullPath(selectedRemote) .. ":InvokeServer()"
        setclipboard(code)
        ButtonFeedback(CopyInvokeBtn, "✅ Código copiado!")
    else
        ButtonFeedback(CopyInvokeBtn, "❌ setclipboard não suportado", colors.red)
    end
end)

CopyScriptBtn.MouseButton1Click:Connect(function()
    if not selectedRemote then
        ButtonFeedback(CopyScriptBtn, "❌ Selecione um remote", colors.red)
        return
    end
    
    local success, script = pcall(function()
        return getcallingscript and getcallingscript() or getfenv().script
    end)
    
    if success and script then
        if hasSetClipboard then
            setclipboard(GetFullPath(script))
            ButtonFeedback(CopyScriptBtn, "✅ Script copiado!")
        else
            ButtonFeedback(CopyScriptBtn, "❌ setclipboard não suportado", colors.red)
        end
    else
        ButtonFeedback(CopyScriptBtn, "❌ Não foi possível obter script", colors.red)
    end
end)

DecompileBtn.MouseButton1Click:Connect(function()
    if not selectedRemote then
        ButtonFeedback(DecompileBtn, "❌ Selecione um remote", colors.red)
        return
    end
    
    if not hasDecompile then
        ButtonFeedback(DecompileBtn, "❌ decompile não suportado", colors.red)
        return
    end
    
    local success, script = pcall(function()
        return getcallingscript and getcallingscript() or getfenv().script
    end)
    
    if not success or not script then
        ButtonFeedback(DecompileBtn, "❌ Script não encontrado", colors.red)
        return
    end
    
    DecompileBtn.Text = "⏳ Decompilando..."
    
    task.spawn(function()
        local success2, result = pcall(function()
            return decompile(script)
        end)
        
        if success2 and hasSetClipboard then
            setclipboard(result)
            ButtonFeedback(DecompileBtn, "✅ Decompile copiado!", colors.green, 2)
        else
            ButtonFeedback(DecompileBtn, "❌ Erro ao decompile", colors.red, 2)
        end
    end)
end)

TestFireBtn.MouseButton1Click:Connect(function()
    if not selectedRemote then
        ButtonFeedback(TestFireBtn, "❌ Selecione um remote", colors.red)
        return
    end
    
    local success, err = pcall(function()
        if selectedRemote:IsA("RemoteEvent") then
            selectedRemote:FireServer()
        else
            ButtonFeedback(TestFireBtn, "⚠️ Use InvokeServer para Functions", colors.orange)
        end
    end)
    
    if success then
        ButtonFeedback(TestFireBtn, "✅ FireServer executado!")
    else
        ButtonFeedback(TestFireBtn, "❌ Erro: " .. tostring(err):sub(1, 20), colors.red)
    end
end)

TestInvokeBtn.MouseButton1Click:Connect(function()
    if not selectedRemote then
        ButtonFeedback(TestInvokeBtn, "❌ Selecione um remote", colors.red)
        return
    end
    
    local success, result = pcall(function()
        if selectedRemote:IsA("RemoteFunction") then
            return selectedRemote:InvokeServer()
        else
            ButtonFeedback(TestInvokeBtn, "⚠️ Use FireServer para Events", colors.orange)
            return nil
        end
    end)
    
    if success then
        if hasSetClipboard and result then
            setclipboard(tostring(result))
            ButtonFeedback(TestInvokeBtn, "✅ Retorno copiado!")
        else
            ButtonFeedback(TestInvokeBtn, "✅ InvokeServer executado!")
        end
    else
        ButtonFeedback(TestInvokeBtn, "❌ Erro: " .. tostring(result):sub(1, 20), colors.red)
    end
end)

-- Keybind
UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == settings.Keybind then
        ScreenGui.Enabled = not ScreenGui.Enabled
    end
end)

-- Scan inicial
task.wait(0.5)
ScanRemotes("")

print("🐢 TurtleSpy V3.0 carregado com sucesso!")
print("📌 Pressione 'P' para abrir/fechar")
print("🔍 Clique em 'Escanear Remotes' para atualizar a lista")
print("💡 Selecione um remote para ver suas informações")
