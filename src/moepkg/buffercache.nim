#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[tables, deques, times, options, logging, strformat]

import bufferstatus, unicodeext, highlight, independentutils, gapbuffer

# Constants for memory estimation
const
  BASE_BUFFER_OVERHEAD = 1024 # Base overhead in bytes
  AVERAGE_LINE_LENGTH = 80 # Assumed average characters per line
  BYTES_PER_CHAR = 4 # Bytes per character (UTF-8 worst case)
  DEFAULT_BUFFER_SIZE = 8192 # Default buffer size in bytes when estimation fails
  BYTES_PER_MB = 1024 * 1024 # Bytes in a megabyte

type
  BufferState* = object ## Cached state for a buffer to restore quickly
    cursorLine*: int
    cursorColumn*: int
    expandedColumn*: int
    scrollY*: int
    scrollX*: int
    selectedArea*: Option[SelectedArea]
    lastAccessTime*: DateTime
    highlight*: Highlight # Cached syntax highlighting
    version*: Natural # Buffer version when state was saved

  CachedBuffer* = object ## A cached buffer with its state
    bufStatus*: BufferStatus
    state*: BufferState
    lastAccessTime*: DateTime
    memorySize*: int # Estimated memory usage in bytes

  BufferCache* = object ## LRU cache for buffers with size limits
    cache*: Table[int, CachedBuffer] # bufferId -> CachedBuffer
    pathToId*: Table[string, int] # file path -> bufferId
    accessOrder*: Deque[int] # LRU order (most recent at back)
    maxCacheSize*: int # Maximum number of buffers to cache
    maxMemoryMB*: int # Maximum memory usage in MB
    currentMemoryBytes*: int # Current memory usage
    hitCount*: int # Cache hit statistics
    missCount*: int # Cache miss statistics
    enabled*: bool # Whether caching is enabled

proc estimateBufferMemory(bufStatus: BufferStatus): int =
  ## Estimate memory usage of a buffer in bytes
  result = BASE_BUFFER_OVERHEAD

  # Use a safer estimation based on file size if available
  try:
    # Simple estimation: assume average line length
    let lineCount = len(bufStatus.buffer)
    result += lineCount * AVERAGE_LINE_LENGTH * BYTES_PER_CHAR
  except CatchableError as e:
    error fmt"estimateBufferMemory: {e.msg}"
    # If buffer access fails, use default estimate
    result += DEFAULT_BUFFER_SIZE

proc moveToBack(accessOrder: var Deque[int], bufferId: int) =
  ## Helper function to move a buffer ID to the back of the access order queue
  ## This is more efficient than recreating the entire deque
  var tempDeque = initDeque[int]()
  var found = false

  # First pass: collect all items except the target
  while len(accessOrder) > 0:
    let id = accessOrder.popFirst()
    if id == bufferId:
      found = true
    else:
      tempDeque.addLast(id)

  # Restore the deque without the target item
  accessOrder = tempDeque

  # Add the target item to the back (most recently used)
  if found:
    accessOrder.addLast(bufferId)

proc removeFromAccessOrder(accessOrder: var Deque[int], bufferId: int) =
  ## Helper function to remove a buffer ID from the access order queue
  var tempDeque = initDeque[int]()

  # Collect all items except the target
  while len(accessOrder) > 0:
    let id = accessOrder.popFirst()
    if id != bufferId:
      tempDeque.addLast(id)

  # Restore the deque without the target item
  accessOrder = tempDeque

proc initBufferCache*(
    maxCacheSize: int = 10, maxMemoryMB: int = 100, enabled: bool = true
): BufferCache =
  ## Initialize a new buffer cache
  BufferCache(
    cache: initTable[int, CachedBuffer](),
    pathToId: initTable[string, int](),
    accessOrder: initDeque[int](),
    maxCacheSize: maxCacheSize,
    maxMemoryMB: maxMemoryMB,
    currentMemoryBytes: 0,
    hitCount: 0,
    missCount: 0,
    enabled: enabled,
  )

proc setEnabled*(cache: var BufferCache, enabled: bool) =
  ## Enable or disable the cache
  cache.enabled = enabled
  if not enabled:
    cache.cache.clear()
    cache.pathToId.clear()
    cache.accessOrder.clear()
    cache.currentMemoryBytes = 0

proc saveBufferState*(
    cache: var BufferCache,
    bufferId: int,
    cursorLine, cursorColumn, expandedColumn: int,
    scrollY, scrollX: int,
    selectedArea: Option[SelectedArea] = none[SelectedArea](),
    highlight: Highlight,
    version: Natural = 0,
) =
  ## Save current buffer state for quick restoration
  if bufferId in cache.cache:
    let now = now()
    cache.cache[bufferId].state = BufferState(
      cursorLine: cursorLine,
      cursorColumn: cursorColumn,
      expandedColumn: expandedColumn,
      scrollY: scrollY,
      scrollX: scrollX,
      selectedArea: selectedArea,
      lastAccessTime: now,
      highlight: highlight,
      version: version,
    )
    cache.cache[bufferId].lastAccessTime = now

proc evictLeastRecentlyUsed(cache: var BufferCache) =
  ## Remove the least recently used buffer from cache
  if len(cache.accessOrder) == 0:
    return

  let bufferId = cache.accessOrder.popFirst()
  if bufferId in cache.cache:
    let cachedBuffer = cache.cache[bufferId]
    cache.currentMemoryBytes -= cachedBuffer.memorySize

    # Remove from path mapping
    let path = $cachedBuffer.bufStatus.path
    if path in cache.pathToId and cache.pathToId[path] == bufferId:
      cache.pathToId.del(path)

    cache.cache.del(bufferId)

proc evictOldBuffers(cache: var BufferCache) =
  ## Evict buffers until within memory/size limits
  let maxMemoryBytes = cache.maxMemoryMB * BYTES_PER_MB

  while (
    len(cache.cache) > cache.maxCacheSize or cache.currentMemoryBytes > maxMemoryBytes
  ) and len(cache.accessOrder) > 0
  :
    cache.evictLeastRecentlyUsed()

proc addToCache*(cache: var BufferCache, bufStatus: BufferStatus) =
  ## Add a buffer to the cache
  if not cache.enabled:
    return

  let bufferId = bufStatus.id
  let memSize = estimateBufferMemory(bufStatus)
  let now = now()

  # If buffer already in cache, update it
  if bufferId in cache.cache:
    cache.currentMemoryBytes -= cache.cache[bufferId].memorySize
    # Remove from access order to re-add at end
    cache.accessOrder.removeFromAccessOrder(bufferId)

  # Add to cache
  cache.cache[bufferId] = CachedBuffer(
    bufStatus: bufStatus,
    state: BufferState(lastAccessTime: now),
    lastAccessTime: now,
    memorySize: memSize,
  )

  cache.currentMemoryBytes += memSize
  cache.accessOrder.addLast(bufferId)

  # Add path mapping
  let path = $bufStatus.path
  if path.len > 0:
    cache.pathToId[path] = bufferId

  # Evict old buffers if necessary
  cache.evictOldBuffers()

proc getFromCache*(cache: var BufferCache, bufferId: int): Option[CachedBuffer] =
  ## Get a buffer from cache, updating access time
  if not cache.enabled:
    inc cache.missCount
    return none[CachedBuffer]()

  if bufferId in cache.cache:
    inc cache.hitCount
    let now = now()

    # Update access time
    cache.cache[bufferId].lastAccessTime = now

    # Move to end of access order (most recently used)
    cache.accessOrder.moveToBack(bufferId)

    return some(cache.cache[bufferId])
  else:
    inc cache.missCount
    return none[CachedBuffer]()

proc getFromCacheByPath*(cache: var BufferCache, path: string): Option[CachedBuffer] =
  ## Get a buffer from cache by file path
  if not cache.enabled:
    inc cache.missCount
    return none[CachedBuffer]()

  if path in cache.pathToId:
    let bufferId = cache.pathToId[path]
    return cache.getFromCache(bufferId)
  else:
    inc cache.missCount
    return none[CachedBuffer]()

proc removeFromCache*(cache: var BufferCache, bufferId: int) =
  ## Remove a specific buffer from cache
  if bufferId in cache.cache:
    let cachedBuffer = cache.cache[bufferId]
    cache.currentMemoryBytes -= cachedBuffer.memorySize

    # Remove from path mapping
    let path = $cachedBuffer.bufStatus.path
    if path in cache.pathToId and cache.pathToId[path] == bufferId:
      cache.pathToId.del(path)

    # Remove from access order
    cache.accessOrder.removeFromAccessOrder(bufferId)

    cache.cache.del(bufferId)

proc isInCache*(cache: BufferCache, bufferId: int): bool =
  ## Check if a buffer is in cache
  bufferId in cache.cache

proc isInCacheByPath*(cache: BufferCache, path: string): bool =
  ## Check if a buffer is in cache by path
  path in cache.pathToId

proc getCacheStats*(
    cache: BufferCache
): tuple[hits, misses: int, hitRate: float, memoryMB: float] =
  ## Get cache performance statistics
  let total = cache.hitCount + cache.missCount
  let hitRate =
    if total > 0:
      cache.hitCount.float / total.float
    else:
      0.0
  let memoryMB = cache.currentMemoryBytes.float / BYTES_PER_MB.float

  (hits: cache.hitCount, misses: cache.missCount, hitRate: hitRate, memoryMB: memoryMB)

proc clearCache*(cache: var BufferCache) =
  ## Clear all cached buffers
  cache.cache.clear()
  cache.pathToId.clear()
  cache.accessOrder.clear()
  cache.currentMemoryBytes = 0
  cache.hitCount = 0
  cache.missCount = 0

proc getCachedBufferIds*(cache: BufferCache): seq[int] =
  ## Get all cached buffer IDs in access order (least to most recent)
  result = @[]
  for bufferId in cache.accessOrder:
    result.add(bufferId)
