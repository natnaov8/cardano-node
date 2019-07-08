{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE MultiWayIf          #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}

{-# OPTIONS_GHC -Wno-simplifiable-class-constraints #-}

module LiveView (
      runNodeLiveView
    ) where

import           Data.Text (unpack)
import           Data.Version (showVersion)
import           Terminal.Game

import           GitRev (gitRev)
import           Ouroboros.Consensus.NodeId
import           Paths_cardano_node (version)
import           Topology

runNodeLiveView :: TopologyInfo -> IO ()
runNodeLiveView topology = playGame game
  where
    game = Game
        { gScreenWidth   = mw
        , gScreenHeight  = mh
        , gFPS           = 13
        , gInitState     = initLiveViewState topology
        , gLogicFunction = liveViewLogic
        , gDrawFunction  = liveViewDraw
        , gQuitFunction  = lvsQuit
        }

mh :: Height
mh = 25

mw :: Width
mw = 95

data LiveViewState = LiveViewState
    { lvsQuit            :: Bool
    , lvsRelease         :: String
    , lvsNodeId          :: Int
    , lvsVersion         :: String
    , lvsCommit          :: String
    , lvsUpTime          :: String
    , lvsBlockHeight     :: Int
    , lvsBlocksMinted    :: Int
    , lvsTransactions    :: Int
    , lvsPeersConnected  :: Int
    , lvsMaxNetDelay     :: Int
    , lvsMempool         :: Int
    , lvsMempoolPerc     :: Int
    , lvsCPUUsagePerc    :: Int
    , lvsMemoryUsageCurr :: Int
    , lvsMemoryUsageMax  :: Int
    } deriving (Show, Eq)

initLiveViewState
    :: TopologyInfo
    -> LiveViewState
initLiveViewState (TopologyInfo nodeId _) = LiveViewState
    { lvsQuit            = False
    , lvsRelease         = "Shelley"   -- Should be taken from ..?
    , lvsNodeId          = nodeIdNum
    , lvsVersion         = showVersion version
    , lvsCommit          = unpack gitRev
    , lvsUpTime          = "00:00:00"
    , lvsBlockHeight     = 0
    , lvsBlocksMinted    = 0
    , lvsTransactions    = 0
    , lvsPeersConnected  = 0
    , lvsMaxNetDelay     = 0
    , lvsMempool         = 95
    , lvsMempoolPerc     = 79
    , lvsCPUUsagePerc    = 58
    , lvsMemoryUsageCurr = 3
    , lvsMemoryUsageMax  = 0
    }
  where
    nodeIdNum = case nodeId of
        CoreId num  -> num
        RelayId num -> num

liveViewLogic
    :: LiveViewState
    -> Event
    -> LiveViewState
liveViewLogic lvs (KeyPress 'q') = lvs { lvsQuit = True }
liveViewLogic lvs (KeyPress 'Q') = lvs { lvsQuit = True }
liveViewLogic lvs (KeyPress _)   = lvs
liveViewLogic lvs Tick           = lvs

makeProgressBar :: Int -> Plane
makeProgressBar percentage =
    if percentage < 0 || percentage > 100
    then error "Impossible: percentage is out of range!"
    else blankPlane fullLength (1 :: Height)
       & (1 :: Row, 1 :: Column) % stringPlane "["
                                 # bold
       & (1 :: Row, 2 :: Column) % stringPlane progress
                                 # color progressColor Vivid
       & (1 :: Row, fullLength)  % stringPlane "]"
                                 # bold
  where
    progress       = replicate progressChars '|' ++ replicate emptyChars ' '
    progressColor  = if | percentage <= 50 -> Green
                        | percentage <= 75 -> Yellow
                        | otherwise        -> Red
    progressChars' = round $ (fromIntegral (percentage `div` percPerChar) :: Double)
    progressChars  = if progressChars' == 0 then 1 else progressChars'
    emptyChars     = progressLength - progressChars
    percPerChar    = 100 `div` progressLength
    progressLength = 20
    fullLength :: Integer
    fullLength = fromIntegral progressLength + 2

header :: LiveViewState -> Plane
header lvs = blankPlane (85 :: Width) (1 :: Height)
    & (1 :: Row,  1 :: Column) % stringPlane "CARDANO SL"
                               # bold
    & (1 :: Row, 17 :: Column) % stringPlane ("Release: ")
    & (1 :: Row, 26 :: Column) % (stringPlane $ lvsRelease lvs)
                               # color Cyan Vivid
    & (1 :: Row, 76 :: Column) % stringPlane ("Node: ")
    & (1 :: Row, 82 :: Column) % (stringPlane . show $ lvsNodeId lvs)
                               # color Cyan Vivid
                               # bold

mempoolStats :: LiveViewState -> Plane
mempoolStats lvs = blankPlane (27 :: Width) (3 :: Height)
    & (1 :: Row,  1 :: Column) % stringPlane "Memory pool"
                               # bold
    & (1 :: Row, 19 :: Column) % stringPlane (
                                            (show . lvsMempool $ lvs)
                                         <> " / "
                                         <> (show . lvsMempoolPerc $ lvs) <> "%"
                                         )
                               # color White Vivid
    & (3 :: Row,  3 :: Column) % (makeProgressBar $ lvsMempoolPerc lvs)

cpuStats :: LiveViewState -> Plane
cpuStats lvs = blankPlane (27 :: Width) (3 :: Height)
    & (1 :: Row,  1 :: Column) % stringPlane "CPU usage"
                               # bold
    & (1 :: Row, 19 :: Column) % stringPlane ((show . lvsCPUUsagePerc $ lvs) <> "%")
                               # color White Vivid
    & (3 :: Row,  3 :: Column) % (makeProgressBar $ lvsCPUUsagePerc lvs)

memoryStats :: LiveViewState -> Plane
memoryStats lvs = blankPlane (27 :: Width) (3 :: Height)
    & (1 :: Row,  1 :: Column) % stringPlane "Memory usage"
                               # bold
    & (1 :: Row, 19 :: Column) % stringPlane ((show . lvsMemoryUsageCurr $ lvs) <> " GB")
                               # color White Vivid
    & (3 :: Row,  3 :: Column) % (makeProgressBar $ lvsMemoryUsageCurr lvs)

systemStats :: LiveViewState -> Plane
systemStats lvs = blankPlane (30 :: Width) (17 :: Height)
    & ( 1 :: Row, 1 :: Column) % mempoolStats lvs
    & ( 7 :: Row, 1 :: Column) % cpuStats lvs
    & (13 :: Row, 1 :: Column) % memoryStats lvs

nodeInfoLabels :: Plane
nodeInfoLabels = blankPlane (20 :: Width) (18 :: Height)
    & ( 1 :: Row, 1 :: Column) % stringPlane "version:"
    & ( 2 :: Row, 1 :: Column) % stringPlane "commit:"
    & ( 4 :: Row, 1 :: Column) % stringPlane "uptime:"
    & ( 6 :: Row, 1 :: Column) % stringPlane "block height:"
    & ( 7 :: Row, 1 :: Column) % stringPlane "minted:"
    & ( 9 :: Row, 1 :: Column) % stringPlane "transactions:"
    & (11 :: Row, 1 :: Column) % stringPlane "peers connected:"
    & (13 :: Row, 1 :: Column) % stringPlane "max network delay:"

nodeInfoValues :: LiveViewState -> Plane
nodeInfoValues lvs = blankPlane (15 :: Width) (18 :: Height)
    & ( 1 :: Row,  1 :: Column) % stringPlane (lvsVersion lvs)
                                # color White Vivid # bold
    & ( 2 :: Row,  1 :: Column) % stringPlane (lvsCommit lvs)
                                # color White Vivid # bold
    & ( 4 :: Row,  1 :: Column) % stringPlane (lvsUpTime lvs)
                                # color White Vivid # bold
    & ( 6 :: Row,  1 :: Column) % stringPlane (show . lvsBlockHeight $ lvs)
                                # color White Vivid # bold
    & ( 7 :: Row,  1 :: Column) % stringPlane (show . lvsBlocksMinted $ lvs)
                                # color White Vivid # bold
    & ( 9 :: Row,  1 :: Column) % stringPlane (show . lvsTransactions $ lvs)
                                # color White Vivid # bold
    & (11 :: Row,  1 :: Column) % stringPlane (show . lvsPeersConnected $ lvs)
                                # color White Vivid # bold
    & (13 :: Row,  1 :: Column) % stringPlane ((show . lvsMaxNetDelay $ lvs) <> " ms")
                                # color White Vivid # bold

nodeInfo :: LiveViewState -> Plane
nodeInfo lvs = blankPlane (40 :: Width) (18 :: Height)
    & (1 :: Row,  1 :: Column) % nodeInfoLabels
    & (1 :: Row, 22 :: Column) % nodeInfoValues lvs

liveViewDraw :: LiveViewState -> Plane
liveViewDraw lvs = blankPlane mw mh
    & (1 :: Row,   1 :: Column) % box '*' mw       mh       -- border
    & (2 :: Row,   2 :: Column) % box ' ' (mw - 2) (mh - 2) -- space inside of border
    & (3 :: Row,   7 :: Column) % header lvs
    & (7 :: Row,   9 :: Column) % systemStats lvs
    & (7 :: Row,  55 :: Column) % nodeInfo lvs
