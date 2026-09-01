#requires -version 5.1
<#
PowerShell GUI Builder V2.77
Starts with a real Home tab automatically. Additional TabControl toolbox clicks
create named designer pages. Exported buttons can navigate to any available tab.
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
$script:Updating = $false

function Quote-PS([string]$Text) {
    if ($null -eq $Text) { return "''" }
    return "'" + $Text.Replace("'", "''") + "'"
}
function Safe-Name([string]$Text) {
    $parts = @($Text -split '[^a-zA-Z0-9]+' | Where-Object { $_ })
    $name = ($parts | ForEach-Object {
        if ($_.Length -eq 1) { $_.ToUpperInvariant() }
        else { $_.Substring(0,1).ToUpperInvariant() + $_.Substring(1) }
    }) -join ''
    if ([string]::IsNullOrWhiteSpace($name)) { return 'Page' }
    return $name
}
function Prefix([string]$Type) {
    $map=@{Button='btn';Label='lbl';TextBox='txt';ComboBox='cmb';CheckBox='chk';RadioButton='rdo';ListBox='lst';DataGridView='grid';ProgressBar='progress';GroupBox='grp';Panel='pnl';DateTimePicker='dtp';NumericUpDown='num'}
    if ($map.ContainsKey($Type)) { return $map[$Type] }
    return 'ctrl'
}
function All-Controls {
    $result=@()
    foreach($page in $script:Pages.Values){foreach($control in $page.Surface.Controls){if($control.Tag){$result += $control}}}
    return $result
}
function Unique-ControlName([string]$Type,[string]$Text) {
    $stem=Safe-Name $Text
    if([string]::IsNullOrWhiteSpace($Text)){$stem='New'+$Type}
    $base=(Prefix $Type)+$stem;$candidate=$base;$n=2
    $existing=@(All-Controls|ForEach-Object{$_.Name})
    while($candidate -in $existing){$candidate=$base+$n;$n++}
    return $candidate
}
function New-Meta([string]$Type,[string]$Action='None',[string]$ActionValue='',[string]$SourceMode='None',[string]$SourceValue='') {
    [pscustomobject]@{Type=$Type;Action=$Action;ActionValue=$ActionValue;SourceMode=$SourceMode;SourceValue=$SourceValue}
}
function Page-Names { return @($script:Pages.Keys) }

function Update-Variables {
    if($null -eq $variableList){return}
    $variableList.Items.Clear()
    foreach($control in All-Controls){[void]$variableList.Items.Add('$'+$control.Name)}
}
function Update-Summary {
    if($null -eq $summary){return}
    if($null -eq $script:SelectedControl){$summary.Text='No control selected';return}
    $c=$script:SelectedControl
    $summary.Text="Type: $($c.Tag.Type)`r`nVariable: `$$($c.Name)`r`nLocation: $($c.Left), $($c.Top)`r`nSize: $($c.Width) x $($c.Height)"
}
function Refresh-Targets {
    if($null -eq $targetTabs){return}
    $current=[string]$targetTabs.SelectedItem
    $targetTabs.Items.Clear()
    foreach($page in Page-Names){[void]$targetTabs.Items.Add($page)}
    if($current -and $targetTabs.Items.Contains($current)){$targetTabs.SelectedItem=$current}
    elseif($script:SelectedControl -and $targetTabs.Items.Contains([string]$script:SelectedControl.Tag.ActionValue)){$targetTabs.SelectedItem=[string]$script:SelectedControl.Tag.ActionValue}
    elseif($targetTabs.Items.Count -gt 0){$targetTabs.SelectedIndex=0}
}
function Update-ActionView {
    if($null -eq $actionType){return}
    $nav=[string]$actionType.SelectedItem -eq 'Navigate to tab'
    $targetTabs.Visible=$nav;$actionValue.Visible=-not $nav
    if($nav){Refresh-Targets}
}
function Select-Control([System.Windows.Forms.Control]$Control) {
    $script:Updating=$true
    try{
        $script:SelectedControl=$Control;$propertyGrid.SelectedObject=$Control
        if($Control){$selected.Text='Selected: '+$Control.Name;$actionType.SelectedItem=[string]$Control.Tag.Action;$actionValue.Text=[string]$Control.Tag.ActionValue;Refresh-Targets;if($targetTabs.Items.Contains([string]$Control.Tag.ActionValue)){$targetTabs.SelectedItem=[string]$Control.Tag.ActionValue}}
        else{$selected.Text='Selected: none';$actionType.SelectedItem='None';$actionValue.Text=''}
        Update-ActionView;Update-Summary
    }finally{$script:Updating=$false}
}
function Wire-Control([System.Windows.Forms.Control]$Control) {
    $Control.Add_MouseDown({param($s,$e);if($e.Button -eq [System.Windows.Forms.MouseButtons]::Left){Select-Control $s;$script:IsDragging=$true;$script:DragOffset=$e.Location;$s.Capture=$true}})
    $Control.Add_MouseMove({param($s,$e);if($script:IsDragging -and $e.Button -eq [System.Windows.Forms.MouseButtons]::Left){$s.Left=[Math]::Max(0,$s.Left+$e.X-$script:DragOffset.X);$s.Top=[Math]::Max(0,$s.Top+$e.Y-$script:DragOffset.Y);$propertyGrid.Refresh();Update-Summary;Update-Code}})
    $Control.Add_MouseUp({param($s,$e);$script:IsDragging=$false;$s.Capture=$false;Update-Code})
}
function Delete-Control([System.Windows.Forms.Control]$Control){if($null -eq $Control){return};$script:CurrentSurface.Controls.Remove($Control);$Control.Dispose();Select-Control $null;Update-Variables;Update-Code}
function Duplicate-Control([System.Windows.Forms.Control]$Control){if($null -eq $Control){return};$name=Unique-ControlName $Control.Tag.Type ($Control.Text+' Copy');Add-Control -Type $Control.Tag.Type -Name $name -Text $Control.Text -X ($Control.Left+15) -Y ($Control.Top+15) -Width $Control.Width -Height $Control.Height -Action $Control.Tag.Action -ActionValue $Control.Tag.ActionValue -SourceMode $Control.Tag.SourceMode -SourceValue $Control.Tag.SourceValue}
function Add-ContextMenu([System.Windows.Forms.Control]$Control){$menu=[System.Windows.Forms.ContextMenuStrip]::new();$edit=$menu.Items.Add('Edit Control...');$duplicate=$menu.Items.Add('Duplicate');[void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new());$delete=$menu.Items.Add('Delete');$edit.Add_Click({Edit-Control $Control});$duplicate.Add_Click({Duplicate-Control $Control});$delete.Add_Click({Delete-Control $Control});$Control.ContextMenuStrip=$menu;$Control.Add_DoubleClick({Edit-Control $Control})}

function Add-Control {
    param([string]$Type,[string]$Name,[string]$Text,[int]$X,[int]$Y,[int]$Width=0,[int]$Height=0,[string]$Action='None',[string]$ActionValue='',[string]$SourceMode='None',[string]$SourceValue='')
    $c=New-Object "System.Windows.Forms.$Type";$c.Name=$Name;$c.Text=$Text;$c.Location=[System.Drawing.Point]::new($X,$Y)
    $sizes=@{Button=@(120,32);Label=@(120,24);TextBox=@(180,26);ComboBox=@(180,28);CheckBox=@(150,26);RadioButton=@(150,26);ListBox=@(200,110);DataGridView=@(320,160);ProgressBar=@(220,24);GroupBox=@(300,180);Panel=@(240,150);DateTimePicker=@(200,28);NumericUpDown=@(120,28)}
    if($Width -le 0){$Width=$sizes[$Type][0]};if($Height -le 0){$Height=$sizes[$Type][1]};$c.Size=[System.Drawing.Size]::new($Width,$Height);$c.Tag=New-Meta $Type $Action $ActionValue $SourceMode $SourceValue
    if($Type -in @('ComboBox','ListBox') -and $SourceMode -eq 'Manual values'){foreach($item in @($SourceValue -split "`r?`n"|Where-Object{$_})){[void]$c.Items.Add($item)}}
    if($Type -eq 'DataGridView'){$c.AllowUserToAddRows=$false;$c.RowHeadersVisible=$false;[void]$c.Columns.Add('Preview','Configured data source')}
    Wire-Control $c;Add-ContextMenu $c;$script:CurrentSurface.Controls.Add($c);Select-Control $c;Update-Variables;Update-Code
}

function Control-Dialog([string]$Type,[System.Windows.Forms.Control]$Existing){
    $editing=$null -ne $Existing;$f=[System.Windows.Forms.Form]::new();$f.Text=$(if($editing){"Edit $Type"}else{"Add $Type"});$f.ClientSize=[System.Drawing.Size]::new(560,600);$f.StartPosition='CenterParent';$f.FormBorderStyle='FixedDialog';$f.MaximizeBox=$false
    $l1=[System.Windows.Forms.Label]::new();$l1.Text='Display text';$l1.Location=[System.Drawing.Point]::new(20,20);$l1.AutoSize=$true;$f.Controls.Add($l1);$text=[System.Windows.Forms.TextBox]::new();$text.Location=[System.Drawing.Point]::new(20,42);$text.Width=520;$text.Text=$(if($editing){$Existing.Text}elseif($Type -in @('TextBox','ComboBox','ListBox','DataGridView','ProgressBar')){''}else{$Type});$f.Controls.Add($text)
    $l2=[System.Windows.Forms.Label]::new();$l2.Text='PowerShell variable name';$l2.Location=[System.Drawing.Point]::new(20,80);$l2.AutoSize=$true;$f.Controls.Add($l2);$name=[System.Windows.Forms.TextBox]::new();$name.Location=[System.Drawing.Point]::new(20,102);$name.Width=520;$name.Text=$(if($editing){$Existing.Name}else{Unique-ControlName $Type $text.Text});$f.Controls.Add($name)
    $mode=[System.Windows.Forms.ComboBox]::new();$value=[System.Windows.Forms.TextBox]::new();$target=[System.Windows.Forms.ComboBox]::new();$y=145
    if($Type -eq 'Button'){$label=[System.Windows.Forms.Label]::new();$label.Text='Button action';$label.Location=[System.Drawing.Point]::new(20,$y);$label.AutoSize=$true;$f.Controls.Add($label);$mode.DropDownStyle='DropDownList';[void]$mode.Items.AddRange(@('None','Show message','Run PowerShell code','Call existing function','Open URL','Navigate to tab','Close form'));$mode.Location=[System.Drawing.Point]::new(20,$($y+24));$mode.Width=520;$mode.SelectedItem=$(if($editing){$Existing.Tag.Action}else{'None'});$f.Controls.Add($mode);$value.Multiline=$true;$value.AcceptsReturn=$true;$value.ScrollBars='Both';$value.Location=[System.Drawing.Point]::new(20,$($y+65));$value.Size=[System.Drawing.Size]::new(520,290);$value.Text=$(if($editing){$Existing.Tag.ActionValue}else{''});$f.Controls.Add($value);$target.DropDownStyle='DropDownList';$target.Location=[System.Drawing.Point]::new(20,$($y+65));$target.Width=520;foreach($page in Page-Names){[void]$target.Items.Add($page)};if($editing -and $target.Items.Contains([string]$Existing.Tag.ActionValue)){$target.SelectedItem=[string]$Existing.Tag.ActionValue}elseif($target.Items.Count -gt 0){$target.SelectedIndex=0};$target.Visible=$false;$f.Controls.Add($target);$mode.Add_SelectedIndexChanged({$nav=[string]$mode.SelectedItem -eq 'Navigate to tab';$target.Visible=$nav;$value.Visible=-not $nav})}
    elseif($Type -in @('ComboBox','ListBox','DataGridView')){$label=[System.Windows.Forms.Label]::new();$label.Text='Populate from';$label.Location=[System.Drawing.Point]::new(20,$y);$label.AutoSize=$true;$f.Controls.Add($label);$mode.DropDownStyle='DropDownList';[void]$mode.Items.AddRange(@('Manual values','Existing variable','PowerShell command'));$mode.Location=[System.Drawing.Point]::new(20,$($y+24));$mode.Width=520;$mode.SelectedItem=$(if($editing){$Existing.Tag.SourceMode}else{'Manual values'});$f.Controls.Add($mode);$tip=[System.Windows.Forms.Label]::new();$tip.Text='Use CTRL + ENTER for a new line. ENTER saves.';$tip.ForeColor='DarkGoldenrod';$tip.Location=[System.Drawing.Point]::new(20,$($y+60));$tip.AutoSize=$true;$f.Controls.Add($tip);$value.Multiline=$true;$value.AcceptsReturn=$true;$value.ScrollBars='Both';$value.Location=[System.Drawing.Point]::new(20,$($y+85));$value.Size=[System.Drawing.Size]::new(520,270);$value.Text=$(if($editing){$Existing.Tag.SourceValue}else{''});$f.Controls.Add($value)}
    $error=[System.Windows.Forms.Label]::new();$error.ForeColor='Firebrick';$error.Location=[System.Drawing.Point]::new(20,510);$error.Size=[System.Drawing.Size]::new(300,40);$f.Controls.Add($error);$ok=[System.Windows.Forms.Button]::new();$ok.Text=$(if($editing){'Save Changes'}else{'Add Control'});$ok.Location=[System.Drawing.Point]::new(350,550);$ok.Size=[System.Drawing.Size]::new(100,32);$f.Controls.Add($ok);$cancel=[System.Windows.Forms.Button]::new();$cancel.Text='Cancel';$cancel.Location=[System.Drawing.Point]::new(460,550);$cancel.Size=[System.Drawing.Size]::new(80,32);$cancel.DialogResult='Cancel';$f.Controls.Add($cancel)
    $ok.Add_Click({$newName=$name.Text.Trim().TrimStart('$');if($newName -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*$'){$error.Text='Enter a valid variable name.';return};$owner=All-Controls|Where-Object{$_.Name -eq $newName -and $_ -ne $Existing};if($owner){$error.Text='That variable name exists.';return};$f.DialogResult='OK';$f.Close()});$f.AcceptButton=$ok;$f.CancelButton=$cancel
    if($f.ShowDialog($builder) -ne 'OK'){return $null};$action=if($Type -eq 'Button'){[string]$mode.SelectedItem}else{'None'};$actionValue=if($action -eq 'Navigate to tab'){[string]$target.SelectedItem}else{$value.Text};$sourceMode=if($Type -in @('ComboBox','ListBox','DataGridView')){[string]$mode.SelectedItem}else{'None'};$sourceValue=if($Type -in @('ComboBox','ListBox','DataGridView')){$value.Text}else{''};return [pscustomobject]@{Name=$name.Text.Trim().TrimStart('$');Text=$text.Text;Action=$action;ActionValue=$actionValue;SourceMode=$sourceMode;SourceValue=$sourceValue}
}
function Edit-Control([System.Windows.Forms.Control]$Control){$r=Control-Dialog $Control.Tag.Type $Control;if($null -eq $r){return};$Control.Name=$r.Name;$Control.Text=$r.Text;$Control.Tag.Action=$r.Action;$Control.Tag.ActionValue=$r.ActionValue;$Control.Tag.SourceMode=$r.SourceMode;$Control.Tag.SourceValue=$r.SourceValue;Select-Control $Control;Update-Variables;Update-Code}

function Center-DesignerSurface {
    param(
        [System.Windows.Forms.Panel]$HostPanel,
        [System.Windows.Forms.Panel]$Surface
    )

    if ($null -eq $HostPanel -or $null -eq $Surface) { return }

    $left = [Math]::Max(20, [int](($HostPanel.ClientSize.Width - $Surface.Width) / 2))
    $top = [Math]::Max(20, [int](($HostPanel.ClientSize.Height - $Surface.Height) / 2))
    $Surface.Location = [System.Drawing.Point]::new($left, $top)
}

function Add-Page([string]$PageName) {
    $id = Safe-Name $PageName

    $page = [System.Windows.Forms.TabPage]::new($PageName)
    $page.Name = 'DesignerPage_' + $id
    $page.Padding = [System.Windows.Forms.Padding]::new(0)

    $hostPanel = [System.Windows.Forms.Panel]::new()
    $hostPanel.Name = 'DesignerHost_' + $id
    $hostPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $hostPanel.AutoScroll = $true
    $hostPanel.BackColor = [System.Drawing.Color]::FromArgb(225,225,225)

    $surface = [System.Windows.Forms.Panel]::new()
    $surface.Name = 'Surface_' + $id
    $surface.Size = [System.Drawing.Size]::new([int]$formWidth.Value,[int]$formHeight.Value)
    $surface.BackColor = [System.Drawing.Color]::White
    $surface.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $surface.Add_MouseDown({ Select-Control $null })

    $hostPanel.Controls.Add($surface)
    $page.Controls.Add($hostPanel)
    $page.Tag = $surface

    $hostPanel.Add_Resize({
        Center-DesignerSurface -HostPanel $hostPanel -Surface $surface
    })

    $script:Pages[$PageName] = [pscustomobject]@{
        Page = $page
        Host = $hostPanel
        Surface = $surface
    }

    # Add designer pages by temporarily removing Generated Code, then adding it back.
    # Remove Generated Code temporarily, add the real designer page, then add
    # Generated Code back so the visible order is Home | ... | Generated Code.
    if ($designerTabs.TabPages.Contains($codePage)) {
        $designerTabs.TabPages.Remove($codePage)
    }
    [void]$designerTabs.TabPages.Add($page)
    [void]$designerTabs.TabPages.Add($codePage)

    Center-DesignerSurface -HostPanel $hostPanel -Surface $surface
    $designerTabs.SelectedTab = $page
    $script:CurrentSurface = $surface

    Update-Variables
    Refresh-Targets
    Update-Code
}

function New-PageDialog{$f=[System.Windows.Forms.Form]::new();$f.Text='Add Tab Page';$f.ClientSize=[System.Drawing.Size]::new(400,150);$f.StartPosition='CenterParent';$l=[System.Windows.Forms.Label]::new();$l.Text='Tab page name';$l.Location=[System.Drawing.Point]::new(20,20);$l.AutoSize=$true;$f.Controls.Add($l);$box=[System.Windows.Forms.TextBox]::new();$box.Location=[System.Drawing.Point]::new(20,45);$box.Width=360;$f.Controls.Add($box);$ok=[System.Windows.Forms.Button]::new();$ok.Text='Add';$ok.Location=[System.Drawing.Point]::new(220,95);$ok.DialogResult='OK';$f.Controls.Add($ok);$cancel=[System.Windows.Forms.Button]::new();$cancel.Text='Cancel';$cancel.Location=[System.Drawing.Point]::new(305,95);$cancel.DialogResult='Cancel';$f.Controls.Add($cancel);$f.AcceptButton=$ok;$f.CancelButton=$cancel;if($f.ShowDialog($builder) -eq 'OK' -and -not [string]::IsNullOrWhiteSpace($box.Text)){return $box.Text.Trim()};return $null}

function Model{$items=@();foreach($entry in $script:Pages.GetEnumerator()){foreach($c in $entry.Value.Surface.Controls){if($c.Tag){$items += [ordered]@{Page=$entry.Key;Type=$c.Tag.Type;Name=$c.Name;Text=$c.Text;X=$c.Left;Y=$c.Top;Width=$c.Width;Height=$c.Height;Action=$c.Tag.Action;ActionValue=$c.Tag.ActionValue;SourceMode=$c.Tag.SourceMode;SourceValue=$c.Tag.SourceValue}}}};return [ordered]@{Version='2.77';Form=@{Text=$formTitle.Text;Width=[int]$formWidth.Value;Height=[int]$formHeight.Value};Pages=@($script:Pages.Keys);Controls=$items}}
function Generate-Code{$m=Model;$s=[System.Text.StringBuilder]::new();@('#requires -version 5.1','Add-Type -AssemblyName System.Windows.Forms','Add-Type -AssemblyName System.Drawing','[System.Windows.Forms.Application]::EnableVisualStyles()','','$MainForm=[System.Windows.Forms.Form]::new()',"`$MainForm.Text=$(Quote-PS $m.Form.Text)","`$MainForm.ClientSize=[System.Drawing.Size]::new($($m.Form.Width),$($m.Form.Height))",'$tabsMain=[System.Windows.Forms.TabControl]::new()','$tabsMain.Dock=[System.Windows.Forms.DockStyle]::Fill','$MainForm.Controls.Add($tabsMain)','')|ForEach-Object{[void]$s.AppendLine($_)};foreach($page in $m.Pages){$pv='$tab'+(Safe-Name $page);[void]$s.AppendLine("$pv=[System.Windows.Forms.TabPage]::new($(Quote-PS $page))");[void]$s.AppendLine("[void]`$tabsMain.TabPages.Add($pv)")};[void]$s.AppendLine('');foreach($i in $m.Controls){$v='$'+$i.Name;$pv='$tab'+(Safe-Name $i.Page);[void]$s.AppendLine("$v=[System.Windows.Forms.$($i.Type)]::new()");[void]$s.AppendLine("$v.Text=$(Quote-PS $i.Text)");[void]$s.AppendLine("$v.Location=[System.Drawing.Point]::new($($i.X),$($i.Y))");[void]$s.AppendLine("$v.Size=[System.Drawing.Size]::new($($i.Width),$($i.Height))");if($i.Type -in @('ComboBox','ListBox') -and $i.SourceMode -eq 'Manual values'){foreach($x in @($i.SourceValue-split"`r?`n"|Where-Object{$_})){[void]$s.AppendLine("[void]$v.Items.Add($(Quote-PS $x))")}};if($i.Action -ne 'None'){[void]$s.AppendLine("$v.Add_Click({");if($i.Action -eq 'Navigate to tab'){$target='$tab'+(Safe-Name $i.ActionValue);[void]$s.AppendLine("    `$tabsMain.SelectedTab=$target")}elseif($i.Action -eq 'Show message'){[void]$s.AppendLine("    [System.Windows.Forms.MessageBox]::Show($(Quote-PS $i.ActionValue))")}elseif($i.Action -eq 'Close form'){[void]$s.AppendLine('    $MainForm.Close()')}else{foreach($line in @($i.ActionValue-split"`r?`n")){[void]$s.AppendLine('    '+$line)}};[void]$s.AppendLine('})')};[void]$s.AppendLine("$pv.Controls.Add($v)");[void]$s.AppendLine('')};[void]$s.AppendLine('[void]$MainForm.ShowDialog()');return $s.ToString()}
function Update-Code{if($codePreview){$codePreview.Text=Generate-Code}}
function Save-Design{$d=[System.Windows.Forms.SaveFileDialog]::new();$d.Filter='GUI design (*.psgui.json)|*.psgui.json';$d.FileName='MyTool.psgui.json';if($d.ShowDialog() -eq 'OK'){Model|ConvertTo-Json -Depth 8|Set-Content $d.FileName -Encoding UTF8}}
function Export-Code{$d=[System.Windows.Forms.SaveFileDialog]::new();$d.Filter='PowerShell (*.ps1)|*.ps1';$d.FileName='My-PowerShell-Tool.ps1';if($d.ShowDialog() -eq 'OK'){Generate-Code|Set-Content $d.FileName -Encoding UTF8}}

$builder=[System.Windows.Forms.Form]::new();$builder.Text='PowerShell GUI Builder V2.77';$builder.WindowState='Maximized';$builder.MinimumSize=[System.Drawing.Size]::new(1200,760)
$bar=[System.Windows.Forms.ToolStrip]::new();$bar.Dock='Top';$newBtn=$bar.Items.Add('New');$saveBtn=$bar.Items.Add('Save');$previewBtn=$bar.Items.Add('Preview');$exportBtn=$bar.Items.Add('Export .ps1');$deleteBtn=$bar.Items.Add('Delete');$builder.Controls.Add($bar)
# V2.76 uses a fixed three-column layout so the centre workspace cannot collapse or drift right.
$workspaceLayout = [System.Windows.Forms.TableLayoutPanel]::new()
$workspaceLayout.Name = 'MainWorkspaceLayout'
$workspaceLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$workspaceLayout.RowCount = 1
$workspaceLayout.ColumnCount = 3
$workspaceLayout.Margin = [System.Windows.Forms.Padding]::new(0)
$workspaceLayout.Padding = [System.Windows.Forms.Padding]::new(0)
[void]$workspaceLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute,[single]185))
[void]$workspaceLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent,[single]100))
[void]$workspaceLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute,[single]350))
[void]$workspaceLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent,[single]100))
$builder.Controls.Add($workspaceLayout)
$workspaceLayout.BringToFront()

$toolbox=[System.Windows.Forms.Panel]::new()
$toolbox.Name='ToolboxPanel'
$toolbox.Dock=[System.Windows.Forms.DockStyle]::Fill
$toolbox.AutoScroll=$true
$toolbox.Margin=[System.Windows.Forms.Padding]::new(0)
$workspaceLayout.Controls.Add($toolbox,0,0)
$title=[System.Windows.Forms.Label]::new();$title.Text='TOOLBOX';$title.Font=[System.Drawing.Font]::new('Segoe UI',[single]11,[System.Drawing.FontStyle]::Bold);$title.Location=[System.Drawing.Point]::new(10,10);$title.AutoSize=$true;$toolbox.Controls.Add($title)
$types=@('Button','Label','TextBox','ComboBox','CheckBox','RadioButton','ListBox','DataGridView','ProgressBar','GroupBox','Panel','DateTimePicker','NumericUpDown','TabControl');$y=42
foreach($type in $types){$b=[System.Windows.Forms.Button]::new();$b.Text='+ '+$type;$b.Tag=$type;$b.Location=[System.Drawing.Point]::new(10,$y);$b.Size=[System.Drawing.Size]::new(155,31);$b.Add_Click({param($sender,$e);$t=[string]$sender.Tag;if($t -eq 'TabControl'){$page=New-PageDialog;if($page -and -not $script:Pages.Contains($page)){Add-Page $page};return};$r=Control-Dialog $t $null;if($r){$o=$script:CurrentSurface.Controls.Count*8;Add-Control -Type $t -Name $r.Name -Text $r.Text -X (20+($o%160)) -Y (20+($o%220)) -Action $r.Action -ActionValue $r.ActionValue -SourceMode $r.SourceMode -SourceValue $r.SourceValue}});$toolbox.Controls.Add($b);$y+=36}
$designerTabs=[System.Windows.Forms.TabControl]::new();$designerTabs.Name='CentreDesignerTabs';$designerTabs.Margin=[System.Windows.Forms.Padding]::new(0);$designerTabs.Dock=[System.Windows.Forms.DockStyle]::Fill;$designerTabs.Alignment=[System.Windows.Forms.TabAlignment]::Top;$designerTabs.Multiline=$false;$workspaceLayout.Controls.Add($designerTabs,1,0);$codePage=[System.Windows.Forms.TabPage]::new('Generated Code');$codePage.Name='GeneratedCodePage';[void]$designerTabs.TabPages.Add($codePage);$codePreview=[System.Windows.Forms.TextBox]::new();$codePreview.Dock='Fill';$codePreview.Multiline=$true;$codePreview.ScrollBars='Both';$codePreview.WordWrap=$false;$codePreview.Font=[System.Drawing.Font]::new('Consolas',[single]10);$codePage.Controls.Add($codePreview)
$right=[System.Windows.Forms.TabControl]::new();$right.Name='InspectorTabs';$right.Dock=[System.Windows.Forms.DockStyle]::Fill;$right.Margin=[System.Windows.Forms.Padding]::new(0);$workspaceLayout.Controls.Add($right,2,0);$props=[System.Windows.Forms.TabPage]::new('Properties');$actions=[System.Windows.Forms.TabPage]::new('Click Action');$vars=[System.Windows.Forms.TabPage]::new('Variables');$form=[System.Windows.Forms.TabPage]::new('Form');$right.TabPages.AddRange(@($props,$actions,$vars,$form))
$selected=[System.Windows.Forms.Label]::new();$selected.Text='Selected: none';$selected.Dock='Top';$selected.Height=28;$props.Controls.Add($selected);$summary=[System.Windows.Forms.TextBox]::new();$summary.Dock='Bottom';$summary.Height=92;$summary.Multiline=$true;$summary.ReadOnly=$true;$props.Controls.Add($summary);$propertyGrid=[System.Windows.Forms.PropertyGrid]::new();$propertyGrid.Dock='Fill';$props.Controls.Add($propertyGrid);$propertyGrid.BringToFront();$propertyGrid.Add_PropertyValueChanged({Update-Summary;Update-Code})
$actionType=[System.Windows.Forms.ComboBox]::new();$actionType.DropDownStyle='DropDownList';$actionType.Location=[System.Drawing.Point]::new(12,18);$actionType.Width=300;[void]$actionType.Items.AddRange(@('None','Show message','Run PowerShell code','Call existing function','Open URL','Navigate to tab','Close form'));$actionType.SelectedIndex=0;$actions.Controls.Add($actionType);$actionValue=[System.Windows.Forms.TextBox]::new();$actionValue.Location=[System.Drawing.Point]::new(12,55);$actionValue.Size=[System.Drawing.Size]::new(300,380);$actionValue.Multiline=$true;$actions.Controls.Add($actionValue);$targetTabs=[System.Windows.Forms.ComboBox]::new();$targetTabs.DropDownStyle='DropDownList';$targetTabs.Location=[System.Drawing.Point]::new(12,55);$targetTabs.Width=300;$targetTabs.Visible=$false;$actions.Controls.Add($targetTabs)
$actionType.Add_SelectedIndexChanged({Update-ActionView;if(-not $script:Updating -and $script:SelectedControl){$script:SelectedControl.Tag.Action=[string]$actionType.SelectedItem;if($actionType.SelectedItem -eq 'Navigate to tab' -and $targetTabs.SelectedItem){$script:SelectedControl.Tag.ActionValue=[string]$targetTabs.SelectedItem};Update-Code}});$actionValue.Add_TextChanged({if(-not $script:Updating -and $script:SelectedControl){$script:SelectedControl.Tag.ActionValue=$actionValue.Text;Update-Code}});$targetTabs.Add_SelectedIndexChanged({if(-not $script:Updating -and $script:SelectedControl -and $targetTabs.SelectedItem){$script:SelectedControl.Tag.ActionValue=[string]$targetTabs.SelectedItem;Update-Code}})
$variableList=[System.Windows.Forms.ListBox]::new();$variableList.Dock='Fill';$vars.Controls.Add($variableList);$formTitle=[System.Windows.Forms.TextBox]::new();$formTitle.Text='My PowerShell Tool';$formTitle.Location=[System.Drawing.Point]::new(12,35);$formTitle.Width=300;$form.Controls.Add($formTitle);$formWidth=[System.Windows.Forms.NumericUpDown]::new();$formWidth.Minimum=300;$formWidth.Maximum=2000;$formWidth.Value=700;$formWidth.Location=[System.Drawing.Point]::new(12,85);$form.Controls.Add($formWidth);$formHeight=[System.Windows.Forms.NumericUpDown]::new();$formHeight.Minimum=200;$formHeight.Maximum=1400;$formHeight.Value=500;$formHeight.Location=[System.Drawing.Point]::new(12,135);$form.Controls.Add($formHeight)
$designerTabs.Add_SelectedIndexChanged({if($designerTabs.SelectedTab -and $designerTabs.SelectedTab.Tag -is [System.Windows.Forms.Panel]){$script:CurrentSurface=$designerTabs.SelectedTab.Tag;Select-Control $null}});$formTitle.Add_TextChanged({Update-Code});$formWidth.Add_ValueChanged({foreach($p in $script:Pages.Values){$p.Surface.Width=[int]$formWidth.Value;Center-DesignerSurface -HostPanel $p.Host -Surface $p.Surface};Update-Code});$formHeight.Add_ValueChanged({foreach($p in $script:Pages.Values){$p.Surface.Height=[int]$formHeight.Value;Center-DesignerSurface -HostPanel $p.Host -Surface $p.Surface};Update-Code})
$newBtn.Add_Click({foreach($p in @($script:Pages.Values)){$designerTabs.TabPages.Remove($p.Page)};$script:Pages=[ordered]@{};Add-Page 'Home';Update-Code});$saveBtn.Add_Click({Save-Design});$exportBtn.Add_Click({Export-Code});$previewBtn.Add_Click({$ps=[PowerShell]::Create();try{[void]$ps.AddScript((Generate-Code));[void]$ps.Invoke()}finally{$ps.Dispose()}});$deleteBtn.Add_Click({Delete-Control $script:SelectedControl})
# V2.77: physically add Home to the centre TabControl and force Home to be the
# active designer after WinForms has completed its initial layout pass.
Add-Page 'Home'

function Ensure-HomeDesignerPageVisible {
    if (-not $script:Pages.Contains('Home')) { return }

    $homePage = $script:Pages['Home'].Page
    if (-not $designerTabs.TabPages.Contains($homePage)) {
        if ($designerTabs.TabPages.Contains($codePage)) {
            $designerTabs.TabPages.Remove($codePage)
        }
        [void]$designerTabs.TabPages.Add($homePage)
        [void]$designerTabs.TabPages.Add($codePage)
    }
}

function Select-HomeDesignerPage {
    Ensure-HomeDesignerPageVisible
    if ($script:Pages.Contains('Home')) {
        $homePage = $script:Pages['Home'].Page
        $homeSurface = $script:Pages['Home'].Surface

        if ($null -ne $homePage -and $designerTabs.TabPages.Contains($homePage)) {
            $designerTabs.SelectedTab = $homePage
            $script:CurrentSurface = $homeSurface
            $homePage.Select()
            $homeSurface.Focus()
            Center-DesignerSurface -HostPanel $script:Pages['Home'].Host -Surface $homeSurface
        }
    }
}

# Set the preferred page now, then set it again when the form is actually shown.
Select-HomeDesignerPage
$builder.Add_Shown({
    Select-HomeDesignerPage

    # BeginInvoke runs after the first WinForms layout/selection cycle. This
    # prevents Generated Code from reclaiming the selected tab at startup.
    [void]$builder.BeginInvoke([System.Windows.Forms.MethodInvoker]{
        Select-HomeDesignerPage
    })
})

Update-Code
[void]$builder.ShowDialog()
