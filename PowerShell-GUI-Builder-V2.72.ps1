#requires -version 5.1
<#
.SYNOPSIS
    PowerShell GUI Builder V2.72
.DESCRIPTION
    Multi-page WinForms designer. Every designer page, including Home, exports as
    a real TabPage. Buttons can navigate to any available tab from a dropdown.
#>
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Pages = [ordered]@{}
$script:CurrentSurface = $null
$script:SelectedControl = $null
$script:IsDragging = $false
$script:DragOffset = [System.Drawing.Point]::Empty
$script:UpdatingInspector = $false

function ConvertTo-PSLiteral {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return "''" }
    return "'" + $Text.Replace("'", "''") + "'"
}

function ConvertTo-Identifier {
    param([string]$Text)
    $result = foreach ($part in @($Text -split '[^a-zA-Z0-9]+' | Where-Object { $_ })) {
        if ($part.Length -eq 1) { $part.ToUpperInvariant() }
        else { $part.Substring(0,1).ToUpperInvariant() + $part.Substring(1) }
    }
    $value = $result -join ''
    if ([string]::IsNullOrWhiteSpace($value)) { return 'Page' }
    return $value
}

function Get-ControlPrefix {
    param([string]$Type)
    $map = @{ Button='btn'; Label='lbl'; TextBox='txt'; ComboBox='cmb'; CheckBox='chk'; RadioButton='rdo'; ListBox='lst'; DataGridView='grid'; ProgressBar='progress'; GroupBox='grp'; Panel='pnl'; DateTimePicker='dtp'; NumericUpDown='num' }
    if ($map.ContainsKey($Type)) { return $map[$Type] }
    return 'ctrl'
}

function Get-AllControls {
    $controls = @()
    foreach ($page in $script:Pages.Values) {
        foreach ($control in $page.Surface.Controls) {
            if ($control.Tag) { $controls += $control }
        }
    }
    return $controls
}

function Get-UniqueControlName {
    param([string]$Type,[string]$Text)
    $stem = ConvertTo-Identifier $Text
    if ([string]::IsNullOrWhiteSpace($Text)) { $stem = 'New' + $Type }
    $base = (Get-ControlPrefix $Type) + $stem
    $name = $base
    $number = 2
    $existing = @(Get-AllControls | ForEach-Object { $_.Name })
    while ($name -in $existing) { $name = $base + $number; $number++ }
    return $name
}

function Get-PageNames { return @($script:Pages.Keys) }

function New-Metadata {
    param([string]$Type,[bool]$Exposed,[string]$Action='None',[string]$ActionValue='',[string]$SourceMode='None',[string]$SourceValue='')
    return [pscustomobject]@{ Type=$Type; Exposed=$Exposed; Action=$Action; ActionValue=$ActionValue; SourceMode=$SourceMode; SourceValue=$SourceValue }
}

function Update-Variables {
    if ($null -eq $variablesList) { return }
    $variablesList.Items.Clear()
    foreach ($control in Get-AllControls) {
        if ($control.Tag.Exposed) { [void]$variablesList.Items.Add('$' + $control.Name) }
    }
}

function Update-Summary {
    if ($null -eq $summaryBox) { return }
    if ($null -eq $script:SelectedControl) { $summaryBox.Text = 'No control selected'; return }
    $control = $script:SelectedControl
    $summaryBox.Text = "Type: $($control.Tag.Type)`r`nVariable: `$$($control.Name)`r`nLocation: $($control.Left), $($control.Top)`r`nSize: $($control.Width) x $($control.Height)"
}

function Refresh-NavigationTargets {
    if ($null -eq $navigationTarget) { return }
    $current = [string]$navigationTarget.SelectedItem
    $navigationTarget.Items.Clear()
    foreach ($pageName in Get-PageNames) { [void]$navigationTarget.Items.Add($pageName) }
    if ($current -and $navigationTarget.Items.Contains($current)) { $navigationTarget.SelectedItem = $current }
    elseif ($script:SelectedControl -and $navigationTarget.Items.Contains([string]$script:SelectedControl.Tag.ActionValue)) { $navigationTarget.SelectedItem = [string]$script:SelectedControl.Tag.ActionValue }
    elseif ($navigationTarget.Items.Count -gt 0) { $navigationTarget.SelectedIndex = 0 }
}

function Update-ActionEditor {
    if ($null -eq $actionType) { return }
    $isNavigation = [string]$actionType.SelectedItem -eq 'Navigate to tab'
    $navigationTarget.Visible = $isNavigation
    $actionValue.Visible = -not $isNavigation
    if ($isNavigation) { Refresh-NavigationTargets }
}

function Select-DesignControl {
    param([System.Windows.Forms.Control]$Control)
    $script:UpdatingInspector = $true
    try {
        $script:SelectedControl = $Control
        $propertyGrid.SelectedObject = $Control
        if ($Control) {
            $selectedLabel.Text = 'Selected: ' + $Control.Name
            $actionType.SelectedItem = [string]$Control.Tag.Action
            $actionValue.Text = [string]$Control.Tag.ActionValue
            Refresh-NavigationTargets
            if ($navigationTarget.Items.Contains([string]$Control.Tag.ActionValue)) { $navigationTarget.SelectedItem = [string]$Control.Tag.ActionValue }
        } else {
            $selectedLabel.Text = 'Selected: none'
            $actionType.SelectedItem = 'None'
            $actionValue.Text = ''
        }
        Update-ActionEditor
        Update-Summary
    }
    finally { $script:UpdatingInspector = $false }
}

function Wire-DesignControl {
    param([System.Windows.Forms.Control]$Control)
    $Control.Add_MouseDown({
        param($Sender,$EventArgs)
        if ($EventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            Select-DesignControl $Sender
            $script:IsDragging = $true
            $script:DragOffset = $EventArgs.Location
            $Sender.Capture = $true
        }
    })
    $Control.Add_MouseMove({
        param($Sender,$EventArgs)
        if ($script:IsDragging -and $EventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $Sender.Left = [Math]::Max(0,$Sender.Left + $EventArgs.X - $script:DragOffset.X)
            $Sender.Top = [Math]::Max(0,$Sender.Top + $EventArgs.Y - $script:DragOffset.Y)
            $propertyGrid.Refresh(); Update-Summary; Update-Code
        }
    })
    $Control.Add_MouseUp({ param($Sender,$EventArgs); $script:IsDragging=$false; $Sender.Capture=$false; Update-Code })
}

function Remove-DesignControl {
    param([System.Windows.Forms.Control]$Control)
    if ($null -eq $Control) { return }
    $script:CurrentSurface.Controls.Remove($Control)
    $Control.Dispose()
    Select-DesignControl $null
    Update-Variables
    Update-Code
}

function Duplicate-DesignControl {
    param([System.Windows.Forms.Control]$Control)
    if ($null -eq $Control) { return }
    $name = Get-UniqueControlName $Control.Tag.Type ($Control.Text + ' Copy')
    Add-DesignControl -Type $Control.Tag.Type -Name $name -Text $Control.Text -X ($Control.Left+15) -Y ($Control.Top+15) -Width $Control.Width -Height $Control.Height -Exposed $Control.Tag.Exposed -Action $Control.Tag.Action -ActionValue $Control.Tag.ActionValue -SourceMode $Control.Tag.SourceMode -SourceValue $Control.Tag.SourceValue
}

function Add-ControlMenu {
    param([System.Windows.Forms.Control]$Control)
    $menu = [System.Windows.Forms.ContextMenuStrip]::new()
    $edit = $menu.Items.Add('Edit Control...')
    $duplicate = $menu.Items.Add('Duplicate')
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    $delete = $menu.Items.Add('Delete')
    $edit.Add_Click({ Show-EditDialog $Control })
    $duplicate.Add_Click({ Duplicate-DesignControl $Control })
    $delete.Add_Click({ Remove-DesignControl $Control })
    $Control.ContextMenuStrip = $menu
    $Control.Add_DoubleClick({ Show-EditDialog $Control })
}

function Add-DesignControl {
    param([string]$Type,[string]$Name,[string]$Text,[int]$X,[int]$Y,[int]$Width=0,[int]$Height=0,[bool]$Exposed=$true,[string]$Action='None',[string]$ActionValue='',[string]$SourceMode='None',[string]$SourceValue='')
    $control = New-Object "System.Windows.Forms.$Type"
    $control.Name=$Name; $control.Text=$Text; $control.Location=[System.Drawing.Point]::new($X,$Y)
    $sizes=@{Button=@(120,32);Label=@(120,24);TextBox=@(180,26);ComboBox=@(180,28);CheckBox=@(150,26);RadioButton=@(150,26);ListBox=@(200,110);DataGridView=@(320,160);ProgressBar=@(220,24);GroupBox=@(300,180);Panel=@(240,150);DateTimePicker=@(200,28);NumericUpDown=@(120,28)}
    if ($Width -le 0) { $Width=$sizes[$Type][0] }; if ($Height -le 0) { $Height=$sizes[$Type][1] }
    $control.Size=[System.Drawing.Size]::new($Width,$Height)
    $control.Tag=New-Metadata $Type $Exposed $Action $ActionValue $SourceMode $SourceValue
    if ($Type -in @('ComboBox','ListBox') -and $SourceMode -eq 'Manual values') { foreach ($item in @($SourceValue -split "`r?`n" | Where-Object { $_ })) { [void]$control.Items.Add($item) } }
    if ($Type -eq 'DataGridView') { $control.AllowUserToAddRows=$false; $control.RowHeadersVisible=$false; [void]$control.Columns.Add('Preview','Configured data source') }
    Wire-DesignControl $control
    Add-ControlMenu $control
    $script:CurrentSurface.Controls.Add($control)
    Select-DesignControl $control
    Update-Variables
    Update-Code
}

function Show-ControlDialog {
    param([string]$Type,[System.Windows.Forms.Control]$Existing)
    $isEdit = $null -ne $Existing
    $dialog=[System.Windows.Forms.Form]::new();$dialog.Text=$(if($isEdit){"Edit $Type"}else{"Add $Type"});$dialog.ClientSize=[System.Drawing.Size]::new(560,620);$dialog.StartPosition='CenterParent';$dialog.FormBorderStyle='FixedDialog';$dialog.MaximizeBox=$false
    $textLabel=[System.Windows.Forms.Label]::new();$textLabel.Text='Display text';$textLabel.Location=[System.Drawing.Point]::new(20,20);$textLabel.AutoSize=$true;$dialog.Controls.Add($textLabel)
    $textBox=[System.Windows.Forms.TextBox]::new();$textBox.Location=[System.Drawing.Point]::new(20,42);$textBox.Width=520;$textBox.Text=$(if($isEdit){$Existing.Text}elseif($Type -in @('TextBox','ComboBox','ListBox','DataGridView','ProgressBar')){''}else{$Type});$dialog.Controls.Add($textBox)
    $nameLabel=[System.Windows.Forms.Label]::new();$nameLabel.Text='PowerShell variable name';$nameLabel.Location=[System.Drawing.Point]::new(20,80);$nameLabel.AutoSize=$true;$dialog.Controls.Add($nameLabel)
    $nameBox=[System.Windows.Forms.TextBox]::new();$nameBox.Location=[System.Drawing.Point]::new(20,102);$nameBox.Width=520;$nameBox.Text=$(if($isEdit){$Existing.Name}else{Get-UniqueControlName $Type $textBox.Text});$dialog.Controls.Add($nameBox)
    $mode=[System.Windows.Forms.ComboBox]::new();$value=[System.Windows.Forms.TextBox]::new();$target=[System.Windows.Forms.ComboBox]::new();$y=145
    if($Type -eq 'Button'){$ml=[System.Windows.Forms.Label]::new();$ml.Text='Button action';$ml.Location=[System.Drawing.Point]::new(20,$y);$ml.AutoSize=$true;$dialog.Controls.Add($ml);$mode.DropDownStyle='DropDownList';[void]$mode.Items.AddRange(@('None','Show message','Run PowerShell code','Call existing function','Open URL','Navigate to tab','Close form'));$mode.Location=[System.Drawing.Point]::new(20,$($y+24));$mode.Width=520;$mode.SelectedItem=$(if($isEdit){$Existing.Tag.Action}else{'None'});$dialog.Controls.Add($mode);$value.Multiline=$true;$value.AcceptsReturn=$true;$value.ScrollBars='Both';$value.Location=[System.Drawing.Point]::new(20,$($y+65));$value.Size=[System.Drawing.Size]::new(520,300);$value.Text=$(if($isEdit){$Existing.Tag.ActionValue}else{''});$dialog.Controls.Add($value);$target.DropDownStyle='DropDownList';$target.Location=[System.Drawing.Point]::new(20,$($y+65));$target.Width=520;foreach($pageName in Get-PageNames){[void]$target.Items.Add($pageName)};if($isEdit -and $target.Items.Contains([string]$Existing.Tag.ActionValue)){$target.SelectedItem=[string]$Existing.Tag.ActionValue}elseif($target.Items.Count -gt 0){$target.SelectedIndex=0};$target.Visible=$false;$dialog.Controls.Add($target);$mode.Add_SelectedIndexChanged({$nav=[string]$mode.SelectedItem -eq 'Navigate to tab';$target.Visible=$nav;$value.Visible=-not $nav})}
    elseif($Type -in @('ComboBox','ListBox','DataGridView')){$ml=[System.Windows.Forms.Label]::new();$ml.Text='Populate from';$ml.Location=[System.Drawing.Point]::new(20,$y);$ml.AutoSize=$true;$dialog.Controls.Add($ml);$mode.DropDownStyle='DropDownList';[void]$mode.Items.AddRange(@('Manual values','Existing variable','PowerShell command'));$mode.Location=[System.Drawing.Point]::new(20,$($y+24));$mode.Width=520;$mode.SelectedItem=$(if($isEdit){$Existing.Tag.SourceMode}else{'Manual values'});$dialog.Controls.Add($mode);$tip=[System.Windows.Forms.Label]::new();$tip.Text='Use CTRL + ENTER for a new line. ENTER saves.';$tip.ForeColor='DarkGoldenrod';$tip.Location=[System.Drawing.Point]::new(20,$($y+60));$tip.AutoSize=$true;$dialog.Controls.Add($tip);$value.Multiline=$true;$value.AcceptsReturn=$true;$value.ScrollBars='Both';$value.Location=[System.Drawing.Point]::new(20,$($y+85));$value.Size=[System.Drawing.Size]::new(520,280);$value.Text=$(if($isEdit){$Existing.Tag.SourceValue}else{''});$dialog.Controls.Add($value)}
    $error=[System.Windows.Forms.Label]::new();$error.ForeColor='Firebrick';$error.Location=[System.Drawing.Point]::new(20,535);$error.Size=[System.Drawing.Size]::new(300,45);$dialog.Controls.Add($error)
    $ok=[System.Windows.Forms.Button]::new();$ok.Text=$(if($isEdit){'Save Changes'}else{'Add Control'});$ok.Location=[System.Drawing.Point]::new(350,570);$ok.Size=[System.Drawing.Size]::new(100,32);$dialog.Controls.Add($ok)
    $cancel=[System.Windows.Forms.Button]::new();$cancel.Text='Cancel';$cancel.Location=[System.Drawing.Point]::new(460,570);$cancel.Size=[System.Drawing.Size]::new(80,32);$cancel.DialogResult='Cancel';$dialog.Controls.Add($cancel)
    $ok.Add_Click({$newName=$nameBox.Text.Trim().TrimStart('$');if($newName -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*$'){$error.Text='Enter a valid variable name.';return};$owner=(Get-AllControls|Where-Object{$_.Name -eq $newName -and $_ -ne $Existing});if($owner){$error.Text='That name already exists.';return};$dialog.DialogResult='OK';$dialog.Close()});$dialog.AcceptButton=$ok;$dialog.CancelButton=$cancel
    if($dialog.ShowDialog($builder) -ne 'OK'){return $null}
    $action=$(if($Type -eq 'Button'){[string]$mode.SelectedItem}else{'None'});$actionValue=$(if($action -eq 'Navigate to tab'){[string]$target.SelectedItem}else{$value.Text});$sourceMode=$(if($Type -in @('ComboBox','ListBox','DataGridView')){[string]$mode.SelectedItem}else{'None'});$sourceValue=$(if($Type -in @('ComboBox','ListBox','DataGridView')){$value.Text}else{''})
    return [pscustomobject]@{Name=$nameBox.Text.Trim().TrimStart('$');Text=$textBox.Text;Action=$action;ActionValue=$actionValue;SourceMode=$sourceMode;SourceValue=$sourceValue}
}

function Show-EditDialog { param([System.Windows.Forms.Control]$Control);$result=Show-ControlDialog $Control.Tag.Type $Control;if($null -eq $result){return};$Control.Name=$result.Name;$Control.Text=$result.Text;$Control.Tag.Action=$result.Action;$Control.Tag.ActionValue=$result.ActionValue;$Control.Tag.SourceMode=$result.SourceMode;$Control.Tag.SourceValue=$result.SourceValue;Select-DesignControl $Control;Update-Variables;Update-Code }

function Add-Page {
    param([string]$PageName)
    $identifier=ConvertTo-Identifier $PageName
    $page=[System.Windows.Forms.TabPage]::new($PageName);$page.Name='Designer_'+$identifier
    $hostPanel=[System.Windows.Forms.Panel]::new();$hostPanel.Dock='Fill';$hostPanel.AutoScroll=$true;$hostPanel.BackColor=[System.Drawing.Color]::FromArgb(225,225,225)
    $surface=[System.Windows.Forms.Panel]::new();$surface.Name='Surface_'+$identifier;$surface.Location=[System.Drawing.Point]::new(20,20);$surface.Size=[System.Drawing.Size]::new([int]$formWidth.Value,[int]$formHeight.Value);$surface.BackColor='White';$surface.BorderStyle='FixedSingle';$surface.Add_MouseDown({Select-DesignControl $null})
    $hostPanel.Controls.Add($surface);$page.Controls.Add($hostPanel);$page.Tag=$surface
    $script:Pages[$PageName]=[pscustomobject]@{Page=$page;Surface=$surface}
    $designerTabs.TabPages.Insert($designerTabs.TabPages.Count-1,$page);$designerTabs.SelectedTab=$page;$script:CurrentSurface=$surface
    Update-Variables;Refresh-NavigationTargets;Update-Code
}

function Show-NewPageDialog {
    $dialog=[System.Windows.Forms.Form]::new();$dialog.Text='Add Tab Page';$dialog.ClientSize=[System.Drawing.Size]::new(400,150);$dialog.StartPosition='CenterParent';$label=[System.Windows.Forms.Label]::new();$label.Text='Tab page name';$label.Location=[System.Drawing.Point]::new(20,20);$label.AutoSize=$true;$dialog.Controls.Add($label);$box=[System.Windows.Forms.TextBox]::new();$box.Location=[System.Drawing.Point]::new(20,45);$box.Width=360;$dialog.Controls.Add($box);$ok=[System.Windows.Forms.Button]::new();$ok.Text='Add';$ok.Location=[System.Drawing.Point]::new(220,95);$ok.DialogResult='OK';$dialog.Controls.Add($ok);$cancel=[System.Windows.Forms.Button]::new();$cancel.Text='Cancel';$cancel.Location=[System.Drawing.Point]::new(305,95);$cancel.DialogResult='Cancel';$dialog.Controls.Add($cancel);$dialog.AcceptButton=$ok;$dialog.CancelButton=$cancel;if($dialog.ShowDialog($builder) -eq 'OK' -and -not [string]::IsNullOrWhiteSpace($box.Text)){return $box.Text.Trim()};return $null
}

function Get-Model {
    $items=@();foreach($entry in $script:Pages.GetEnumerator()){foreach($control in $entry.Value.Surface.Controls){if($control.Tag){$items += [ordered]@{Page=$entry.Key;Type=$control.Tag.Type;Name=$control.Name;Text=$control.Text;X=$control.Left;Y=$control.Top;Width=$control.Width;Height=$control.Height;Exposed=$control.Tag.Exposed;Action=$control.Tag.Action;ActionValue=$control.Tag.ActionValue;SourceMode=$control.Tag.SourceMode;SourceValue=$control.Tag.SourceValue}}}}
    return [ordered]@{Version='2.72';Form=@{Text=$formTitle.Text;Width=[int]$formWidth.Value;Height=[int]$formHeight.Value};Pages=@($script:Pages.Keys);Controls=$items}
}

function Get-GeneratedCode {
    $model=Get-Model;$code=[System.Text.StringBuilder]::new();@('#requires -version 5.1','Add-Type -AssemblyName System.Windows.Forms','Add-Type -AssemblyName System.Drawing','[System.Windows.Forms.Application]::EnableVisualStyles()','','$MainForm=[System.Windows.Forms.Form]::new()',"`$MainForm.Text=$(ConvertTo-PSLiteral $model.Form.Text)","`$MainForm.ClientSize=[System.Drawing.Size]::new($($model.Form.Width),$($model.Form.Height))","`$MainForm.StartPosition='CenterScreen'",'','$tabsMain=[System.Windows.Forms.TabControl]::new()','$tabsMain.Dock=[System.Windows.Forms.DockStyle]::Fill','$MainForm.Controls.Add($tabsMain)','')|ForEach-Object{[void]$code.AppendLine($_)}
    foreach($pageName in $model.Pages){$pv='$tab'+(ConvertTo-Identifier $pageName);[void]$code.AppendLine("$pv=[System.Windows.Forms.TabPage]::new($(ConvertTo-PSLiteral $pageName))");[void]$code.AppendLine("[void]`$tabsMain.TabPages.Add($pv)")};[void]$code.AppendLine('')
    foreach($item in $model.Controls){$v='$'+$item.Name;$pv='$tab'+(ConvertTo-Identifier $item.Page);[void]$code.AppendLine("$v=[System.Windows.Forms.$($item.Type)]::new()");[void]$code.AppendLine("$v.Name=$(ConvertTo-PSLiteral $item.Name)");[void]$code.AppendLine("$v.Text=$(ConvertTo-PSLiteral $item.Text)");[void]$code.AppendLine("$v.Location=[System.Drawing.Point]::new($($item.X),$($item.Y))");[void]$code.AppendLine("$v.Size=[System.Drawing.Size]::new($($item.Width),$($item.Height))")
        if($item.Type -in @('ComboBox','ListBox')){if($item.SourceMode -eq 'Manual values'){foreach($x in @($item.SourceValue-split"`r?`n"|Where-Object{$_})){[void]$code.AppendLine("[void]$v.Items.Add($(ConvertTo-PSLiteral $x))")}}elseif($item.SourceMode -eq 'Existing variable'){[void]$code.AppendLine("[void]$v.Items.AddRange(@($($item.SourceValue)))")}elseif($item.SourceMode -eq 'PowerShell command'){[void]$code.AppendLine("[void]$v.Items.AddRange(@(& { $($item.SourceValue) }))")}}
        if($item.Action -ne 'None'){[void]$code.AppendLine("$v.Add_Click({");if($item.Action -eq 'Navigate to tab'){$target='$tab'+(ConvertTo-Identifier $item.ActionValue);[void]$code.AppendLine("    `$tabsMain.SelectedTab=$target")}elseif($item.Action -eq 'Show message'){[void]$code.AppendLine("    [System.Windows.Forms.MessageBox]::Show($(ConvertTo-PSLiteral $item.ActionValue))")}elseif($item.Action -eq 'Open URL'){[void]$code.AppendLine("    Start-Process $(ConvertTo-PSLiteral $item.ActionValue)")}elseif($item.Action -eq 'Close form'){[void]$code.AppendLine('    $MainForm.Close()')}else{foreach($line in @($item.ActionValue-split"`r?`n")){[void]$code.AppendLine('    '+$line)}};[void]$code.AppendLine('})')};[void]$code.AppendLine("$pv.Controls.Add($v)");[void]$code.AppendLine('')}
    [void]$code.AppendLine('[void]$MainForm.ShowDialog()');return $code.ToString()
}
function Update-Code { if($codePreview){$codePreview.Text=Get-GeneratedCode} }
function Save-Design {$d=[System.Windows.Forms.SaveFileDialog]::new();$d.Filter='GUI design (*.psgui.json)|*.psgui.json';$d.FileName='MyTool.psgui.json';if($d.ShowDialog() -eq 'OK'){Get-Model|ConvertTo-Json -Depth 8|Set-Content $d.FileName -Encoding UTF8}}
function Export-Code {$d=[System.Windows.Forms.SaveFileDialog]::new();$d.Filter='PowerShell (*.ps1)|*.ps1';$d.FileName='My-PowerShell-Tool.ps1';if($d.ShowDialog() -eq 'OK'){Get-GeneratedCode|Set-Content $d.FileName -Encoding UTF8}}

$builder=[System.Windows.Forms.Form]::new();$builder.Text='PowerShell GUI Builder V2.72';$builder.WindowState='Maximized';$builder.MinimumSize=[System.Drawing.Size]::new(1200,760)
$bar=[System.Windows.Forms.ToolStrip]::new();$bar.Dock='Top';$newButton=$bar.Items.Add('New');$saveButton=$bar.Items.Add('Save');$previewButton=$bar.Items.Add('Preview');$exportButton=$bar.Items.Add('Export .ps1');$deleteButton=$bar.Items.Add('Delete');$builder.Controls.Add($bar)
$mainSplit=[System.Windows.Forms.SplitContainer]::new();$mainSplit.Dock='Fill';$mainSplit.SplitterDistance=185;$builder.Controls.Add($mainSplit);$mainSplit.BringToFront()
$toolbox=[System.Windows.Forms.Panel]::new();$toolbox.Dock='Fill';$toolbox.AutoScroll=$true;$mainSplit.Panel1.Controls.Add($toolbox);$toolTitle=[System.Windows.Forms.Label]::new();$toolTitle.Text='TOOLBOX';$toolTitle.Font=[System.Drawing.Font]::new('Segoe UI',[single]11,[System.Drawing.FontStyle]::Bold);$toolTitle.Location=[System.Drawing.Point]::new(10,10);$toolTitle.AutoSize=$true;$toolbox.Controls.Add($toolTitle)
$types=@('Button','Label','TextBox','ComboBox','CheckBox','RadioButton','ListBox','DataGridView','ProgressBar','GroupBox','Panel','DateTimePicker','NumericUpDown','TabControl');$y=42
foreach($type in $types){$button=[System.Windows.Forms.Button]::new();$button.Text='+ '+$type;$button.Tag=$type;$button.Location=[System.Drawing.Point]::new(10,$y);$button.Size=[System.Drawing.Size]::new(155,31);$button.Add_Click({param($sender,$e);$typeName=[string]$sender.Tag;if($typeName -eq 'TabControl'){$pageName=Show-NewPageDialog;if($pageName -and -not $script:Pages.Contains($pageName)){Add-Page $pageName};return};$result=Show-ControlDialog $typeName $null;if($result){$offset=$script:CurrentSurface.Controls.Count*8;Add-DesignControl -Type $typeName -Name $result.Name -Text $result.Text -X (20+($offset%160)) -Y (20+($offset%220)) -Action $result.Action -ActionValue $result.ActionValue -SourceMode $result.SourceMode -SourceValue $result.SourceValue}});$toolbox.Controls.Add($button);$y+=36}
$workSplit=[System.Windows.Forms.SplitContainer]::new();$workSplit.Dock='Fill';$workSplit.SplitterDistance=720;$mainSplit.Panel2.Controls.Add($workSplit)
$designerTabs=[System.Windows.Forms.TabControl]::new();$designerTabs.Dock='Fill';$workSplit.Panel1.Controls.Add($designerTabs);$generatedPage=[System.Windows.Forms.TabPage]::new('Generated Code');$designerTabs.TabPages.Add($generatedPage);$codePreview=[System.Windows.Forms.TextBox]::new();$codePreview.Dock='Fill';$codePreview.Multiline=$true;$codePreview.ScrollBars='Both';$codePreview.WordWrap=$false;$codePreview.Font=[System.Drawing.Font]::new('Consolas',[single]10);$generatedPage.Controls.Add($codePreview)
$rightTabs=[System.Windows.Forms.TabControl]::new();$rightTabs.Dock='Fill';$workSplit.Panel2.Controls.Add($rightTabs);$propsPage=[System.Windows.Forms.TabPage]::new('Properties');$actionsPage=[System.Windows.Forms.TabPage]::new('Click Action');$variablesPage=[System.Windows.Forms.TabPage]::new('Variables');$formPage=[System.Windows.Forms.TabPage]::new('Form');$rightTabs.TabPages.AddRange(@($propsPage,$actionsPage,$variablesPage,$formPage))
$selectedLabel=[System.Windows.Forms.Label]::new();$selectedLabel.Text='Selected: none';$selectedLabel.Dock='Top';$selectedLabel.Height=28;$propsPage.Controls.Add($selectedLabel);$summaryBox=[System.Windows.Forms.TextBox]::new();$summaryBox.Dock='Bottom';$summaryBox.Height=92;$summaryBox.Multiline=$true;$summaryBox.ReadOnly=$true;$propsPage.Controls.Add($summaryBox);$propertyGrid=[System.Windows.Forms.PropertyGrid]::new();$propertyGrid.Dock='Fill';$propsPage.Controls.Add($propertyGrid);$propertyGrid.BringToFront();$propertyGrid.Add_PropertyValueChanged({Update-Summary;Update-Code})
$actionType=[System.Windows.Forms.ComboBox]::new();$actionType.DropDownStyle='DropDownList';$actionType.Location=[System.Drawing.Point]::new(12,18);$actionType.Width=300;[void]$actionType.Items.AddRange(@('None','Show message','Run PowerShell code','Call existing function','Open URL','Navigate to tab','Close form'));$actionType.SelectedIndex=0;$actionsPage.Controls.Add($actionType)
$actionValue=[System.Windows.Forms.TextBox]::new();$actionValue.Location=[System.Drawing.Point]::new(12,55);$actionValue.Size=[System.Drawing.Size]::new(300,380);$actionValue.Multiline=$true;$actionValue.ScrollBars='Both';$actionsPage.Controls.Add($actionValue);$navigationTarget=[System.Windows.Forms.ComboBox]::new();$navigationTarget.DropDownStyle='DropDownList';$navigationTarget.Location=[System.Drawing.Point]::new(12,55);$navigationTarget.Width=300;$navigationTarget.Visible=$false;$actionsPage.Controls.Add($navigationTarget)
$actionType.Add_SelectedIndexChanged({Update-ActionEditor;if(-not $script:UpdatingInspector -and $script:SelectedControl){$script:SelectedControl.Tag.Action=[string]$actionType.SelectedItem;if($actionType.SelectedItem -eq 'Navigate to tab' -and $navigationTarget.SelectedItem){$script:SelectedControl.Tag.ActionValue=[string]$navigationTarget.SelectedItem};Update-Code}});$actionValue.Add_TextChanged({if(-not $script:UpdatingInspector -and $script:SelectedControl){$script:SelectedControl.Tag.ActionValue=$actionValue.Text;Update-Code}});$navigationTarget.Add_SelectedIndexChanged({if(-not $script:UpdatingInspector -and $script:SelectedControl -and $navigationTarget.SelectedItem){$script:SelectedControl.Tag.ActionValue=[string]$navigationTarget.SelectedItem;Update-Code}})
$variablesList=[System.Windows.Forms.ListBox]::new();$variablesList.Dock='Fill';$variablesPage.Controls.Add($variablesList)
$formTitle=[System.Windows.Forms.TextBox]::new();$formTitle.Text='My PowerShell Tool';$formTitle.Location=[System.Drawing.Point]::new(12,35);$formTitle.Width=300;$formPage.Controls.Add($formTitle);$formWidth=[System.Windows.Forms.NumericUpDown]::new();$formWidth.Minimum=300;$formWidth.Maximum=2000;$formWidth.Value=700;$formWidth.Location=[System.Drawing.Point]::new(12,85);$formPage.Controls.Add($formWidth);$formHeight=[System.Windows.Forms.NumericUpDown]::new();$formHeight.Minimum=200;$formHeight.Maximum=1400;$formHeight.Value=500;$formHeight.Location=[System.Drawing.Point]::new(12,135);$formPage.Controls.Add($formHeight)
$designerTabs.Add_SelectedIndexChanged({if($designerTabs.SelectedTab -and $designerTabs.SelectedTab.Tag -is [System.Windows.Forms.Panel]){$script:CurrentSurface=$designerTabs.SelectedTab.Tag;Select-DesignControl $null}})
$formTitle.Add_TextChanged({Update-Code});$formWidth.Add_ValueChanged({foreach($page in $script:Pages.Values){$page.Surface.Width=[int]$formWidth.Value};Update-Code});$formHeight.Add_ValueChanged({foreach($page in $script:Pages.Values){$page.Surface.Height=[int]$formHeight.Value};Update-Code})
$newButton.Add_Click({foreach($page in @($script:Pages.Values)){$designerTabs.TabPages.Remove($page.Page)};$script:Pages=[ordered]@{};Add-Page 'Home';Update-Code});$saveButton.Add_Click({Save-Design});$exportButton.Add_Click({Export-Code});$previewButton.Add_Click({$ps=[PowerShell]::Create();try{[void]$ps.AddScript((Get-GeneratedCode));[void]$ps.Invoke()}finally{$ps.Dispose()}});$deleteButton.Add_Click({Remove-DesignControl $script:SelectedControl})
Add-Page 'Home'
Update-Code
[void]$builder.ShowDialog()
