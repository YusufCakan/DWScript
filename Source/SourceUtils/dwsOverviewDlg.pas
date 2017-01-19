{**********************************************************************}
{                                                                      }
{    "The contents of this file are subject to the Mozilla Public      }
{    License Version 1.1 (the "License"); you may not use this         }
{    file except in compliance with the License. You may obtain        }
{    a copy of the License at http://www.mozilla.org/MPL/              }
{                                                                      }
{    Software distributed under the License is distributed on an       }
{    "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express       }
{    or implied. See the License for the specific language             }
{    governing rights and limitations under the License.               }
{                                                                      }
{    Copyright Creative IT.                                            }
{    Current maintainer: Eric Grange                                   }
{                                                                      }
{**********************************************************************}
unit dwsOverviewDlg;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ComCtrls, ImgList, ToolWin,
  dwsExprs, dwsScriptSource, dwsSymbolDictionary, dwsSymbols, dwsUtils;

type
   TIconIndex = (
      iiClass = 0, iiInterface, iiEnum, iiType, iiRecord,
      iiMethodPrivate, iiMethodProtected, iiMethodPublic, iiFunction,
      iiSource
      );
   TIconIndexSet = set of TIconIndex;

  TdwsOverviewDialog = class(TForm)
    TreeView: TTreeView;
    ImageList: TImageList;
    ToolBar: TToolBar;
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeViewExpanding(Sender: TObject; Node: TTreeNode;
      var AllowExpansion: Boolean);
    procedure TreeViewKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormDeactivate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure TreeViewDblClick(Sender: TObject);
    procedure TreeViewAdvancedCustomDrawItem(Sender: TCustomTreeView;
      Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage;
      var PaintImages, DefaultDraw: Boolean);
    procedure FormDestroy(Sender: TObject);

   private
      { Private declarations }
      FProg : IdwsProgram;
      FScriptPos : TScriptPos;
      FOnGoToScriptPos : TNotifyEvent;
      FFilter : TIconIndexSet;
      FExpandedNodes : TStringList;

      procedure FilterChanged(sender : TObject);

      procedure ValidateSelection;

      procedure CollectExpandedNodes(parent : TTreeNode);
      procedure ApplyExpandedNodes(parent : TTreeNode);

      procedure RefreshTree;
      procedure AddSymbolsOfSourceFile(root : TTreeNode; const sourceFile : TSourceFile);
      procedure AddSymbolsOfComposite(parent : TTreeNode; const sourceFile : TSourceFile);

  public
      { Public declarations }
      procedure Execute(const aProg : IdwsProgram; const aScriptPos : TScriptPos);

      property Filter : TIconIndexSet read FFilter write FFilter;
      property ScriptPos : TScriptPos read FScriptPos;
      property OnGoToScriptPos : TNotifyEvent read FOnGoToScriptPos write FOnGoToScriptPos;
  end;

implementation

{$R *.dfm}

const cIconIndexHints : array [TIconIndex] of String = (
      'Classes', 'Interfaces', 'Enumerations', 'other Types', 'Records',
      'Private Methods', 'Protected Methods', 'Public & Published Methods', 'Functions & Procedures',
      'Source file'
      );

// ------------------
// ------------------ TdwsOverviewDialog ------------------
// ------------------

procedure TdwsOverviewDialog.FormCreate(Sender: TObject);
var
   i : TIconIndex;
   tb : TToolButton;
begin
   FExpandedNodes := TStringList.Create;

   for i := iiFunction downto iiClass do begin
      if i in [iiRecord] then begin
         tb := TToolButton.Create(ToolBar);
         tb.Style := tbsSeparator;
         tb.Parent := ToolBar;
         tb.Width := 7;
         tb.Tag := -1;
      end;

      tb := TToolButton.Create(ToolBar);
      tb.ImageIndex := Ord(i);
      tb.Parent := ToolBar;
      tb.Style := tbsCheck;
      tb.Tag := Ord(i);
      tb.OnClick := FilterChanged;
      tb.Hint := 'Show or hide ' + cIconIndexHints[i];
      Include(FFilter, i);
   end;
end;

procedure TdwsOverviewDialog.FormDestroy(Sender: TObject);
begin
   FExpandedNodes.Free;
end;

procedure TdwsOverviewDialog.FormClose(Sender: TObject;
  var Action: TCloseAction);
begin
   if TreeView.Items.Count > 0 then begin
      CollectExpandedNodes(nil);
      TreeView.Items.Clear;
   end;
   FProg := nil;
end;

procedure TdwsOverviewDialog.FormDeactivate(Sender: TObject);
begin
   if Visible then
      Close;
end;

procedure TdwsOverviewDialog.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
   if Key = 27 then Close;
end;

// Execute
//
procedure TdwsOverviewDialog.Execute(const aProg : IdwsProgram; const aScriptPos : TScriptPos);
begin
   FProg := aProg;
   FScriptPos := aScriptPos;

   if aProg.Msgs.HasErrors then
      Caption := 'Overview - INCOMPLETE because the code has errors'
   else Caption := 'Overview';

   RefreshTree;

   Show;
end;

// RefreshTree
//
procedure TdwsOverviewDialog.RefreshTree;
var
   root : TTreeNode;
begin
   TreeView.Items.BeginUpdate;
   try
      if TreeView.Items.Count > 0 then
         CollectExpandedNodes(nil);
      TreeView.Items.Clear;

      root := TreeView.Items.AddFirst(nil, FScriptPos.SourceFile.Name);
      root.ImageIndex := Ord(iiSource);
      root.SelectedIndex := Ord(iiSource);
      AddSymbolsOfSourceFile(root, FScriptPos.SourceFile);
      root.Expand(False);
      if root.Count = 1 then
         root.getFirstChild.Expand(False);

      ApplyExpandedNodes(nil);
   finally
      TreeView.Items.EndUpdate;
   end;
end;

procedure TdwsOverviewDialog.TreeViewAdvancedCustomDrawItem(
  Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
  Stage: TCustomDrawStage; var PaintImages, DefaultDraw: Boolean);
var
   r : TRect;
   txt : String;
   p : Integer;
   symbol : TSymbol;
begin
   PaintImages := True;
   DefaultDraw := (Stage <> cdPostPaint) or (Node.Data = nil);
   if not DefaultDraw then begin
      r := Node.DisplayRect(True);
      r.Left := r.Right + 10;
      r.Right := TreeView.Width;
      if (GetWindowLong(TreeView.Handle, GWL_STYLE) and WS_VSCROLL) <> 0 then
         r.Right := r.Right - GetSystemMetrics(SM_CXVSCROLL);
      symbol := TSymbolPositionList(Node.Data).Symbol;
      txt := symbol.Description;
      p := Pos( LowerCase(symbol.Name), LowerCase(txt) );
      if p > 0 then begin
         txt := Trim(Copy(txt, 1, p-1)) + ' ' + Trim(Copy(txt, p + Length(symbol.Name)));
         txt := Trim(StrBeforeChar(txt, #13));
      end else txt := '';
      if txt <> '' then begin
         TreeView.Canvas.Font.Size := 8;
         TreeView.Canvas.Font.Name := 'Segoe UI';
         TreeView.Canvas.Font.Color := $AAAAAA;
         TreeView.Canvas.TextRect(r, txt, [tfLeft, tfSingleLine, tfVerticalCenter, tfEndEllipsis]);
      end;
   end;
end;

// FilterChanged
//
procedure TdwsOverviewDialog.FilterChanged(sender : TObject);
var
   i : TIconIndex;
begin
   i := TIconIndex((sender as TToolButton).Tag);
   if (sender as TToolButton).Down then
      Exclude(FFilter, i)
   else Include(FFilter, i);
   RefreshTree;
end;

procedure TdwsOverviewDialog.TreeViewDblClick(Sender: TObject);
begin
   ValidateSelection;
end;

// ValidateSelection
//
procedure TdwsOverviewDialog.ValidateSelection;
var
   node : TTreeNode;
   symPosList : TSymbolPositionList;
   symPos : TSymbolPosition;
begin
   node := TreeView.Selected;
   if node = nil then Exit;

   symPosList := TSymbolPositionList(node.Data);
   if symPosList = nil then Exit;
   if symPosList.Count = 0 then Exit;

   symPos := symPosList.FindUsage(suImplementation);
   if symPos = nil then begin
      symPos := symPosList.FindUsage(suDeclaration);
      if symPos = nil then
         symPos := symPosList[0];
   end;

   FScriptPos := symPos.ScriptPos;
   if Assigned(FOnGoToScriptPos) then
      FOnGoToScriptPos(Self);
   Close;
end;

// CollectExpandedNodes
//
procedure TdwsOverviewDialog.CollectExpandedNodes(parent : TTreeNode);
var
   child : TTreeNode;
begin
   if parent = nil then begin
      FExpandedNodes.Clear;
      child := TreeView.Items.GetFirstNode;
   end else child := parent.getFirstChild;
   while child <> nil do begin
      if child.HasChildren and child.Expanded then begin
         if child.Data<>nil then
            FExpandedNodes.Add(TSymbolPositionList(child.Data).Symbol.QualifiedName);
         CollectExpandedNodes(child);
      end;
      child := child.getNextSibling;
   end;
end;

// ApplyExpandedNodes
//
procedure TdwsOverviewDialog.ApplyExpandedNodes(parent : TTreeNode);
var
   child : TTreeNode;
begin
   if parent = nil then begin
      if FExpandedNodes.Count = 0 then Exit;
      child := TreeView.Items.GetFirstNode;
   end else child := parent.getFirstChild;
   while child <> nil do begin
      if child.Data <> nil then begin
         if FExpandedNodes.IndexOf(TSymbolPositionList(child.Data).Symbol.QualifiedName) >= 0 then begin
            child.Expand(False);
            ApplyExpandedNodes(child);
         end;
      end else if child.Expanded then
         ApplyExpandedNodes(child);
      child := child.getNextSibling;
   end;
end;

procedure TdwsOverviewDialog.TreeViewExpanding(Sender: TObject; Node: TTreeNode;
  var AllowExpansion: Boolean);
begin
   if (Node.Count = 1) and (Node.getFirstChild.Text = '') then
      AddSymbolsOfComposite(Node, FScriptPos.SourceFile);
   AllowExpansion := True;
end;

procedure TdwsOverviewDialog.TreeViewKeyUp(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
   if Key = 13 then
      ValidateSelection;
end;

// AddSymbolsOfSourceFile
//
function CompareDeclaration(Item1, Item2: Pointer): Integer;
begin
   Result := TSymbolPositionList(Item1).FindUsage(suDeclaration).ScriptPos
            .Compare(TSymbolPositionList(Item2).FindUsage(suDeclaration).ScriptPos);
end;
procedure TdwsOverviewDialog.AddSymbolsOfSourceFile(root : TTreeNode; const sourceFile : TSourceFile);
var
   symPosList : TSymbolPositionList;
   symPos : TSymbolPosition;
   node : TTreeNode;
   symbolClass : TClass;
   localSymbols : TList;
   iconIndex : TIconIndex;
   i : Integer;
begin
   localSymbols := TList.Create;
   try
      for symPosList in FProg.SymbolDictionary do begin
         if symPosList.Symbol.Name='' then continue;
         if     (symPosList.Symbol is TTypeSymbol)
            and not (symPosList.Symbol is TMethodSymbol) then begin

            for symPos in symPosList do begin
               if (symPos.ScriptPos.SourceFile = sourceFile) and (suDeclaration in symPos.SymbolUsages) then begin
                  localSymbols.Add(symPosList);
                  break;
               end;
            end;
         end;
      end;

      localSymbols.Sort(CompareDeclaration);
      for i := 0 to localSymbols.Count-1 do begin
         symPosList := TSymbolPositionList(localSymbols[i]);

         symbolClass := symPosList.Symbol.ClassType;

         if symbolClass.InheritsFrom(TClassSymbol) then begin
            iconIndex := iiClass;
         end else if symbolClass.InheritsFrom(TRecordSymbol) then begin
            iconIndex := iiRecord;
         end else if symbolClass.InheritsFrom(TInterfaceSymbol) then begin
            iconIndex := iiInterface;
         end else if symbolClass.InheritsFrom(TEnumerationSymbol) then begin
            iconIndex := iiEnum;
         end else if symbolClass.InheritsFrom(TFuncSymbol) and (not symPosList.Symbol.IsType) then
            iconIndex := iiFunction
         else iconIndex := iiType;

         if iconIndex in FFilter then begin
            node := TreeView.Items.AddChild(root, symPosList.Symbol.Name);
            if iconIndex in [iiClass, iiRecord] then
               TreeView.Items.AddChild(node, '');
            node.Data := symPosList;
            node.ImageIndex := Ord(iconIndex);
            node.SelectedIndex := Ord(iconIndex);
         end;
      end;
   finally
      localSymbols.Free;
   end;
end;

// AddSymbolsOfComposite
//
procedure TdwsOverviewDialog.AddSymbolsOfComposite(parent : TTreeNode; const sourceFile : TSourceFile);
var
   symbol : TSymbol;
   symPosList : TSymbolPositionList;
   composite : TCompositeTypeSymbol;
   iconIndex : TIconIndex;
   node : TTreeNode;
   members : TList;
   i : Integer;
begin
   composite := TSymbolPositionList(parent.Data).Symbol as TCompositeTypeSymbol;
   parent.DeleteChildren;

   members := TList.Create;
   try
      for symbol in composite.Members do begin
         if symbol.Name='' then continue;
         symPosList := FProg.SymbolDictionary.FindSymbolPosList(symbol);
         if symPosList = nil then continue;
         if symbol is TMethodSymbol then begin
            members.Add(symPosList);
         end;
      end;
      members.Sort(CompareDeclaration);
      for i := 0 to members.Count-1 do begin
         symPosList := TSymbolPositionList(members[i]);
         if symPosList.FindAnyUsageInFile([suDeclaration, suImplementation], sourceFile) = nil then continue;
         symbol := symPosList.Symbol;
         if symbol is TMethodSymbol then begin
            case TMethodSymbol(symbol).Visibility of
               cvPrivate :   iconIndex := iiMethodPrivate;
               cvProtected : iconIndex := iiMethodProtected;
            else
               iconIndex := iiMethodPublic;
            end;
         end else iconIndex := iiFunction;
         if iconIndex in FFilter then begin
            node := TreeView.Items.AddChild(parent, symbol.Name);
            node.Data := symPosList;
            node.ImageIndex := Ord(iconIndex);
            node.SelectedIndex := Ord(iconIndex);
         end;
      end;
   finally
      members.Free;
   end;
end;

end.