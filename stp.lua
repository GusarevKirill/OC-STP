-- Simple Transmission Protocol v0.1.0 by Kirgus
-- Протокол STP - это примитивная обёртка над сетевой картой, которая позволяет отправителю убедиться в том, что данные дошли до адресата.
-- В первоначальной версии применяется текстовый заголовок сегмента. В дальнейшем заголовок должен кодироваться в бинарный код для компактности.
--------------------------------
local com = require("component")
local modem = com.modem
local event = require("event")
local logging = require("logging")
--------------------------------
local maxPacketSize = modem.maxPacketSize() - 2
local headerSize = nil  -- A size of a header that will be included in each packet
--local maxPayloadSize = maxPacketSize - headerSize  -- Max payload size per segment
--local headerPattern = "%4s:%5s:%5s:"
local headerPattern = "%4s:%3s:"
--local dataOffset = 13
local ACK_OFFSET = 10
local dataOffset = 4 + 1 + 3 + 1
local maxAttempts = 5
--------------------------------
local awaitingList = {}
local listenerId
local logger = logging.getLogger("./stp.log")
--------------------------------
---- После тестирования убрать функцию sendSegment из таблицы stcp и дать функции модификатор local
--function stcp.sendSegment(address, port, data)
--  segment = addHeader(data)
--  modem.send(address, port, segment)
--end

--local function addHeader(payload)
--  local segment = nil
--  return segment
--end

--function stcp.sendPacket(address, port, data)
--  if #data > maxPayloadSize then
--    -- Разобрать data на сегменты
--  else
--    -- Отправить data единым сегментом без деления
--  end
--end

-- Returns: string
local function extractPayload(packet)
  local dataOffset = ACK_OFFSET - 1
  local payload = packet:sub(1 + dataOffset)
  return payload
end

-- Returns: string
local function extractHeader(packet)
  local headerSize = ACK_OFFSET - 1
  local header = packet:sub(1, headerSize)
  return header
end

-- Returns: table
local function structureHeader(header)
  return {}  -- Заглушка
  --local structuredHeader = {protocol="STP"}
  --structuredHeader.version = header:sub(HDR_VERSION_OFFSET, HDR_VERSION_OFFSET + HDR_VERSION_SZ)
  --return structuredHeader
end

-- Returns: nil
local function v1_ack(address, port)
  modem.send(address, port, "STP v0.1\nACK")
end

-- Returns: nil
local function ack(address, port)
  v1_ack(address, port)
end

-- Returns: bool
local function isAck(packet)
  return packet:sub(ACK_OFFSET, ACK_OFFSET + 2) == "ACK"
end

local stp = {}

-- Returns: bool
function stp.send(address, port, data)
  local retval
  local attempts = 0
  --local header = headerPattern:format()
  local header = "STP v0.1\n"
  packet = header .. data
  ::retry::
  modem.send(address, port, packet)
  logger:info(("Sent to %s:%d packet: %s"):format(address, port, packet))
  attempts = attempts + 1
  local isOpen = modem.isOpen(port)
  modem.open(port)
  local _, _, sender, _, _, reply = event.pull("modem_message")
  if isAck(reply) then
    logger:debug(("In stp.send has been received ACK packet from %s.\nContent:\n%s"):format(sender, reply))
    retval = true
  elseif attempts >= maxAttempts then
    logger:debug(("In stp.send has been received regular packet (not ACK) from %s.\nContent:\n%s"):format(sender, reply))
    retval = false
  else
    logger:debug(("In stp.send has been received regular packet (not ACK) from %s.\nContent:\n%s"):format(sender, reply))
    goto retry
  end
  if not isOpen then
    modem.close(port)
  end
  return retval
end

-- Обёртка над event.pull
-- Returns: string
function stp.wait(port)
  isOpen = modem.isOpen(port)
  modem.open(port)
  local _, _, remote_addr, _, _, data = event.pull("modem_message")
  ack(remote_addr, port)
  if not isOpen then
    modem.close(port)
  end
  return data
end

-- Returns: bool
local function isStpHeader(header)
  return header:sub(1, 5) == "STP v"
end

-- Проверяет, является ли data STP-пакетом
-- Returns: bool
local function isStp(data)
  local DATA_OFFSET = ACK_OFFSET
  local header = data:sub(1, 1 + DATA_OFFSET)
  local isStpHeader = isStpHeader(header)
  if isStpHeader then
    return true
  else
    return false
  end
end

-- Обёртка над event.listen
-- Returns: nil
function stp.listen(port, callback)
  local function wrapper(eventName, thisAddr, remoteAddr, localPort, distance, data)
    logger:debug("wrapper CALLED")
    local isStp = isStp(data)
    if isStp then
      logger:debug("isStp IS TRUE")
      local payload = extractPayload(data)
      local header = extractHeader(data)
      local structuredHeader = structureHeader(header)
      if isAck(data) then
        logger:debug("stp.listen.wrapper: isAck(data) => true")
      else
        logger:debug("stp.listen.wrapper: isAck(data) => false")
        ack(remoteAddr, localPort)
        logger:debug("callback CALLING")
        callback(eventName, thisAddr, remoteAddr, localPort, distance, payload, structuredHeader)
        logger:debug("callback CALL FINISHED")
      end
    end
  end
  modem.open(port)
  listenerId = event.listen("modem_message", wrapper)
  logger:info("listenerId: " .. tostring(listenerId))
end

return stp