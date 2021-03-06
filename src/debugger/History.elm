module History exposing
  ( History
  , Frame
  , Source(..)
  , size
  , record
  , timeTravel
  , rebuildCache
  , view
  )
  -- where


import Array
import Html exposing (Html, div, text)
import Html.Events exposing (onClick)
import Html.Lazy exposing (lazy)
import UserProgram exposing (ElmValue, UserProgram)



-- CONSTANTS


maxLeafCount : Int
maxLeafCount =
  128



-- HISTORY


type History =
  History
    { tree : HistoryTree
    , recentModel : ElmValue
    , recentFrames : List Frame
    , recentFramesCount : Int
    , count : Int
    }


type alias Frame =
  { message : ElmValue
  , timestamp : Int
  , source : Source
  }


type Source = User | Cmd Int | Sub


size : History -> Int
size (History history) =
  history.count



-- HISTORY TREES


type HistoryTree
  = Node Int HistoryTree HistoryTree
  | Leaf Epoch


type alias Epoch =
    { model : ElmValue
    , frames : Array.Array Frame
    }


insert : Epoch -> HistoryTree -> HistoryTree
insert epoch tree =
  case tree of
    Leaf _ ->
      Node 1 tree (Leaf epoch)

    Node height full rest ->
      if height - 1 == getHeight rest then
        Node (height + 1) tree (Leaf epoch)

      else
        Node height full (insert epoch rest)


getHeight : HistoryTree -> Int
getHeight tree =
  case tree of
    Leaf _ ->
      0

    Node height _ _ ->
      height



-- RECORD FRAMES


record : Frame -> ElmValue -> History -> History
record frame model (History {tree, recentModel, recentFrames, recentFramesCount, count}) =
  if recentFramesCount == maxLeafCount then
    History
      { tree = insert (Epoch recentModel (Array.fromList recentFrames)) tree
      , recentModel = model
      , recentFrames = [frame]
      , recentFramesCount = 1
      , count = count + 1
      }

  else
    History
      { tree = tree
      , recentModel = recentModel
      , recentFrames = frame :: recentFrames
      , recentFramesCount = recentFramesCount + 1
      , count = count + 1
      }



-- TIME TRAVEL


timeTravel : UserProgram -> Int -> History -> ElmValue
timeTravel userProgram time (History history) =
  let
    historyTreeSize =
      history.count - history.recentFramesCount
  in
    if time < historyTreeSize then
      timeTravelHelp userProgram time history.tree

    else
      fst <|
        List.foldr
          (partialStep userProgram)
          (history.recentModel, time - historyTreeSize)
          history.recentFrames


timeTravelHelp : UserProgram -> Int -> HistoryTree -> ElmValue
timeTravelHelp userProgram time tree =
  case tree of
    Leaf {model, frames} ->
      fst <| Array.foldr (partialStep userProgram) (model, time) frames

    Node height full rest ->
      let
        fullSize =
          2 ^ (height - 1)
      in
        if time < fullSize then
          timeTravelHelp userProgram time full

        else
          timeTravelHelp userProgram (fullSize - time) rest


partialStep : UserProgram -> Frame -> (ElmValue, Int) -> (ElmValue, Int)
partialStep userProgram frame ((model, framesRemaining) as result) =
  if framesRemaining <= 0 then
    result

  else
    ( fst (userProgram.step frame.message model)
    , framesRemaining - 1
    )



-- REBUILD CACHE


rebuildCache : ElmValue -> UserProgram -> History -> History
rebuildCache flags userProgram (History history) =
  let
    initialModel =
      fst (userProgram.init flags)

    (tree, model) =
      rebuildCacheHelp userProgram history.tree initialModel
  in
    History
      { tree = tree
      , recentModel = model
      , recentFrames = history.recentFrames
      , recentFramesCount = history.recentFramesCount
      , count = history.count
      }


rebuildCacheHelp : UserProgram -> HistoryTree -> ElmValue -> (HistoryTree, ElmValue)
rebuildCacheHelp userProgram tree model =
  case tree of
    Leaf {frames} ->
      ( Leaf (Epoch model frames)
      , Array.foldr (step userProgram) model frames
      )

    Node height full rest ->
      let
        (newFull, newModel) =
          rebuildCacheHelp userProgram full model

        (newRest, finalModel) =
          rebuildCacheHelp userProgram rest newModel
      in
        ( Node height newFull newRest
        , finalModel
        )


step : UserProgram -> Frame -> ElmValue -> ElmValue
step userProgram frame model =
  fst (userProgram.step frame.message model)



-- VIEW


view : History -> Html Int
view (History {tree, recentFrames}) =
  let
    oldStuff =
      lazy viewHistoryTree tree

    newStuff =
      List.foldl ((::) << lazy viewFrame) [] recentFrames
  in
    div [] (oldStuff :: newStuff)


viewHistoryTree : HistoryTree -> Html Int
viewHistoryTree tree =
  div [] (viewHistoryTreeHelp tree [])


viewHistoryTreeHelp : HistoryTree -> List (Html Int) -> List (Html Int)
viewHistoryTreeHelp tree epochNodes =
  case tree of
    Leaf epoch ->
      lazy viewLeaf epoch.frames :: epochNodes

    Node _ full rest ->
      viewHistoryTreeHelp full (viewHistoryTreeHelp rest epochNodes)


viewLeaf : Array.Array Frame -> Html Int
viewLeaf frames =
  div [] (Array.foldl ((::) << viewFrame) [] frames)


viewFrame : Frame -> Html Int
viewFrame frame =
  div
    [ onClick frame.timestamp ]
    [ text (toString frame.message)
    ]
