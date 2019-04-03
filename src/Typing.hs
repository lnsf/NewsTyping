module Typing (createGame, startGame, Result(..), TypeCounter(..)) where

import           Config
import           System.IO.NoBufferingWorkaround
import           System.Console.ANSI
import           System.IO
import           System.Timeout
import           System.Exit
import           Data.Time.Clock.System
import           Data.Typing.Record
import           Control.Concurrent

data Game = Game { strs :: [String]
                 , remStrs :: [String]
                 , currentTypedStr :: String
                 , currentRemStr :: String
                 , nextChar :: Char
                 , consoleWidth :: Int
                 }

createGame :: [String] -> IO Game
createGame ss = do
  cw <- do
    s <- getTerminalSize
    w <- case s of
      Nothing     -> return $ (maximum . map length) ss
      Just (_, c) -> return c
    c <- isFixConsoleWidth
    if c
      then return $ w - 1
      else return w
  return $ nextGameString $ Game ss ss "" "" ' ' cw

startGame :: Game -> IO Result
startGame g = do
  initGame
  countDown 3
  s <- (\x -> appendTime (systemSeconds x) (systemNanoseconds x))
    <$> getSystemTime
  t <- typing g Init initialTyped
  f <- (\x -> appendTime (systemSeconds x) (systemNanoseconds x))
    <$> getSystemTime
  return $ Result (f - s) t
  where
    appendTime :: (Show a, Show b) => a -> b -> Double
    appendTime sec nano = read (show sec ++ "." ++ show nano)

nextGameString :: Game -> Game
nextGameString g =
  g { remStrs = rs, currentTypedStr = "", currentRemStr = cs, nextChar = nc }
  where
    rs = (tail . remStrs) g

    (nc:cs) = (head . remStrs) g

nextGameChar :: Game -> Game
nextGameChar g = g { currentTypedStr = ts, currentRemStr = cs, nextChar = nc }
  where
    ts = currentTypedStr g ++ [nextChar g]

    (nc:cs) = currentRemStr g

initGame :: IO ()
initGame = do
  hSetBuffering stdout NoBuffering
  hSetEcho stdout False
  initGetCharNoBuffering

typing :: Game -> TypeCounter -> IO TypeCounter
typing g t = do
  f
  display g (getTypingStatus t)
  c <- getCharNoBuffering
  clear
  checkInput c g t
  where
    checkInput c g t
      | c == nextChar g = typing g (countCorrect t)
      | c == '\ESC' = exitSuccess
      | otherwise = typing g (countMiss t)

    finOrLoop g t
      | didFinishGame g = return t
      | didFinCurrentStr g = typing (nextGameString g) Init (correctType t)
      | otherwise = typing (nextGameChar g) Correct (correctType t)

    didFinCurrentStr = null . currentRemStr

    didFinishGame g = (null . remStrs) g && didFinCurrentStr g

countDown :: Int -> IO ()
countDown s = case s of
  0 -> return ()
  _ -> do
    putStr $ show s
    x <- timeout (2 * sec) (threadDelay sec *> clear)
    case x of
      Just _  -> countDown (s - 1)
      Nothing -> return ()
  where
    sec = 1000000

display :: Game -> Status -> IO ()
display g s = do
  setTypedColor
  putStr displayTyped
  setNextCharColor s
  putChar $ nextChar g
  setRemColor
  putStr displayRem
  where
    displayTyped = drop (max (length typ - consoleWidth g `div` 2) 0) typ

    displayRem = take (consoleWidth g - length displayTyped - 1) rem

    typ = currentTypedStr g

    rem = currentRemStr g

    setNextCharColor s = do
      setDefaultColor
      case s of
        None    -> setSGR [SetColor Foreground Vivid Yellow]
        Correct -> setSGR [SetColor Foreground Vivid Green]
        Miss    -> setSGR [SetColor Background Vivid Red]

    setTypedColor = setSGR [SetColor Foreground Vivid Black]

    setDefaultColor = setSGR [Reset]

    setRemColor = setDefaultColor

clear :: IO ()
clear = do
  clearFromCursorToLineBeginning
  setCursorColumn 0

