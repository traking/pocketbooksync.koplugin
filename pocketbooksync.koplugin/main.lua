local Device = require("device")

if not Device:isPocketBook() then
    return { disabled = true, }
end

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
local util = require("util")
local UIManager = require("ui/uimanager")

local ffi = require("ffi")

ffi.cdef[[
void *bsLoad(const char *);
void bsSetCPage(void *, int);
void bsSetNPage(void *, int);
void bsSetOpenTime(void *, time_t);
int bsClose(void *);
int bsSave(void *);
]]
local pbBookState = ffi.load("libbookstate.so")

local PocketbookSync = WidgetContainer:extend{
    name = "pocketbooksync",
    is_doc_only = false,
}

function PocketbookSync:immediateSync()
    UIManager:unschedule(self.doSync)
    self:doSync(self:prepareSync())
end

function PocketbookSync:scheduleSync()
    UIManager:unschedule(self.doSync)
    UIManager:scheduleIn(3, self.doSync, self, self:prepareSync())
end

function PocketbookSync:prepareSync()
    -- onFlushSettings called during koreader exit and after onCloseDocument
    -- would raise an error in some of the self.document methods and we can
    -- avoid that by checking if self.ui.document is nil
    if not self.ui.document then
        return nil
    end

    local filepath = self.view.document.file
    if not filepath or filepath == "" then
        logger.info("Pocketbook Sync: No folder/file found for " .. self.view.document.file)
        return nil
    end

    local globalPage = self.view.state.page
    local flow = self.document:getPageFlow(globalPage)

    -- skip sync if not in the main flow
    if flow ~= 0 then
        return nil
    end

    local totalPages = self.document:getTotalPagesInFlow(flow)
    local page = self.document:getPageNumberInFlow(globalPage)

    -- hide the progress bar if we're on the title/cover page
    --
    -- we'll never set cpage=1 so the progress bar will seem to jump a bit at
    -- the start of a book, but there's no nice way to fix that: to use the
    -- full range, we'd need to map pages 2 to last-1 to cpages 1 to last-1,
    -- and that always skips one position; skipping the first one is the least
    -- surprising behaviour
    if page == 1 then
        page = 0
    end

    local data = {
        filepath = filepath,
        totalPages = totalPages,
        page = page,
        time = os.time(),
    }
    return data
end

function PocketbookSync:doSync(data)
    if not data then
        return
    end

    if not pbBookState then
        return
    end

    local bookHandle = pbBookState.bsLoad(data.filepath)
    if not bookHandle then
        return
    end

    pbBookState.bsSetCPage(bookHandle, data.page)
    pbBookState.bsSetNPage(bookHandle, data.totalPages)
    pbBookState.bsSetOpenTime(bookHandle, data.time)
    pbBookState.bsSave(bookHandle)
    pbBookState.bsClose(bookHandle)
end

function PocketbookSync:onPageUpdate()
    self:scheduleSync()
end

function PocketbookSync:onFlushSettings()
    self:immediateSync()
end

function PocketbookSync:onCloseDocument()
    self:immediateSync()
end

function PocketbookSync:onEndOfBook()
    self:immediateSync()
end

return PocketbookSync
