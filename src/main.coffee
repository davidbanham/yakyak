Client    = require 'hangupsjs'
Q         = require 'q'
login     = require './login'
ipc       = require 'ipc'
fs        = require 'fs'
path      = require 'path'
tmp       = require 'tmp'
clipboard = require 'clipboard'

tmp.setGracefulCleanup()

app = require 'app'
BrowserWindow = require 'browser-window'

paths =
    rtokenpath:  path.normalize path.join app.getPath('userData'), 'refreshtoken.txt'
    cookiespath: path.normalize path.join app.getPath('userData'), 'cookies.json'
    chromecookie: path.normalize path.join app.getPath('userData'), 'Cookies'

client = new Client
    rtokenpath:  paths.rtokenpath
    cookiespath: paths.cookiespath

if fs.existsSync paths.chromecookie
    fs.unlinkSync paths.chromecookie

plug = (rs, rj) -> (err, val) -> if err then rj(err) else rs(val)

logout = ->
    promise = client.logout()
    promise.then (res) ->
      argv = process.argv
      spawn = require('child_process').spawn
      spawn argv.shift(), argv,
        cwd: process.cwd
        env: process.env
        stdio: 'inherit'
      app.quit()
    return promise # like it matters

seqreq = require './seqreq'

mainWindow = null

# Quit when all windows are closed.
app.on 'window-all-closed', ->
    app.quit() # if (process.platform != 'darwin')

loadAppWindow = ->
    mainWindow.loadUrl 'file://' + __dirname + '/ui/index.html'

# helper wait promise
wait = (t) -> Q.Promise (rs) -> setTimeout rs, t

app.on 'ready', ->

    # Create the browser window.
    mainWindow = new BrowserWindow {
        width: 730
        height: 590
        "min-width": 620
        "min-height": 420
    }

    # and load the index.html of the app. this may however be yanked
    # away if we must do auth.
    loadAppWindow()

    # short hand
    ipcsend = (as...) ->  mainWindow.webContents.send as...

    # callback for credentials
    creds = ->
        prom = login(mainWindow)
        # reinstate app window when login finishes
        prom.then -> loadAppWindow()
        auth: -> prom

    # sends the init structures to the client
    sendInit = ->
        # we have no init data before the client has connected first
        # time.
        return false unless client?.init?.self_entity
        ipcsend 'init', init: client.init
        return true

    # keeps trying to connec the hangupsjs and communicates those
    # attempts to the client.
    reconnect = -> client.connect(creds)

    # counter for reconnects
    reconnectCount = 0
    # first connect
    reconnect().then ->
        console.log 'connected', reconnectCount
        # on first connect, send init, after that only resync
        if reconnectCount == 0
            sendInit()
        else
            syncrecent()
        reconnectCount++

    # client deals with window sizing
    mainWindow.on 'resize', (ev) -> ipcsend 'resize', mainWindow.getSize()
    mainWindow.on 'moved',  (ev) -> ipcsend 'moved', mainWindow.getPosition()

    # whenever it fails, we try again
    client.on 'connect_failed', -> wait(3000).then -> reconnect()

    # when client requests (re-)init since the first init
    # object is sent as soon as possible on startup
    ipc.on 'reqinit', -> syncrecent() if sendInit()

    # sendchatmessage, executed sequentially and
    # retried if not sent successfully
    ipc.on 'sendchatmessage', seqreq (ev, msg) ->
        {conv_id, segs, client_generated_id, image_id, otr} = msg
        client.sendchatmessage(conv_id, segs, image_id, otr, client_generated_id).then (r) ->
            ipcsend 'sendchatmessage:result', r
        , true # do retry

    # no retry, only one outstanding call
    ipc.on 'setpresence', seqreq ->
        client.setpresence(true)
    , false, -> 1

    # no retry, only one outstanding call
    ipc.on 'setactiveclient', seqreq (ev, active, secs) ->
        client.setactiveclient active, secs
    , false, -> 1

    # watermarking is only interesting for the last of each conv_id
    # retry send and dedupe for each conv_id
    ipc.on 'updatewatermark', seqreq (ev, conv_id, time) ->
        client.updatewatermark conv_id, time
    , true, (ev, conv_id, time) -> conv_id

    # getentity is not super important, the client will try again when encountering
    # entities without photo_url. so no retry, but do execute all such reqs
    # ipc.on 'getentity', seqreq (ev, ids) ->
    #     client.getentitybyid(ids).then (r) -> ipcsend 'getentity:result', r
    # , false

    # we want to upload. in the order specified, with retry
    ipc.on 'uploadimage', seqreq (ev, spec) ->
        {path, conv_id, client_generated_id} = spec
        ipcsend 'uploadingimage', {conv_id, client_generated_id, path}
        client.uploadimage(path).then (image_id) ->
            client.sendchatmessage conv_id, null, image_id, null, client_generated_id
    , true

    # we want to upload. in the order specified, with retry
    ipc.on 'uploadclipboardimage', seqreq (ev, spec) ->
        {conv_id, client_generated_id} = spec
        file = tmp.fileSync postfix: ".png"
        pngData = clipboard.readImage().toPng()
        ipcsend 'uploadingimage', {conv_id, client_generated_id, path:file.name}
        Q.Promise (rs, rj) ->
            fs.writeFile file.name, pngData, plug(rs, rj)
        .then ->
            client.uploadimage(file.name)
        .then (image_id) ->
            client.sendchatmessage conv_id, null, image_id, null, client_generated_id
        .then ->
            file.removeCallback()
    , true

    # retry only last per conv_id
    ipc.on 'setconversationnotificationlevel', seqreq (ev, conv_id, level) ->
        client.setconversationnotificationlevel conv_id, level
    , true, (ev, conv_id, level) -> conv_id

    # retry
    ipc.on 'deleteconversation', seqreq (ev, conv_id) ->
        client.deleteconversation conv_id
    , true

    ipc.on 'removeuser', seqreq (ev, conv_id) ->
        client.removeuser conv_id
    , true

    # no retries, dedupe on conv_id
    ipc.on 'setfocus', seqreq (ev, conv_id) ->
        client.setfocus conv_id
    , false, (ev, conv_id) -> conv_id

    ipc.on 'appfocus', -> app.focus()

    # no retries, dedupe on conv_id
    ipc.on 'settyping', seqreq (ev, conv_id, v) ->
        client.settyping conv_id, v
    , false, (ev, conv_id) -> conv_id

    ipc.on 'updatebadge', (ev, value) ->
        app.dock.setBadge(value) if app.dock

    ipc.on 'searchentities', (ev, query, max_results) ->
        promise = client.searchentities query, max_results
        promise.then (res) ->
            ipcsend 'searchentities:result', res
    ipc.on 'createconversation', (ev, ids, name) ->
        promise = client.createconversation ids
        conv = null
        promise.then (res) ->
            conv = res.conversation
            conv_id = conv.id.id
            client.renameconversation conv_id, name if name
        promise = promise.then (res) ->
            ipcsend 'createconversation:result', conv, name
    ipc.on 'adduser', (ev, conv_id, toadd) ->
        client.adduser conv_id, toadd # will automatically trigger membership_change
    ipc.on 'renameconversation', (ev, conv_id, newname) ->
        client.renameconversation conv_id, newname # will trigger conversation_rename

    # no retries, just dedupe on the ids
    ipc.on 'getentity', seqreq (ev, ids, data) ->
        client.getentitybyid(ids).then (r) ->
            ipcsend 'getentity:result', r, data
    , false, (ev, ids) -> ids.sort().join(',')

    # no retry, just one single request
    ipc.on 'syncallnewevents', seqreq (ev, time) ->
        console.log 'syncallnew'
        client.syncallnewevents(time).then (r) ->
            ipcsend 'syncallnewevents:response', r
    , false, (ev, time) -> 1

    # no retry, just one single request
    ipc.on 'syncrecentconversations', syncrecent = seqreq (ev) ->
        console.log 'syncrecent'
        client.syncrecentconversations().then (r) ->
            ipcsend 'syncrecentconversations:response', r
            # this is because we use syncrecent on reqinit (dev-mode
            # refresh). if we succeeded getting a response, we call it
            # connected.
            ipcsend 'connected'
    , false, (ev, time) -> 1

    # retry, one single per conv_id
    ipc.on 'getconversation', seqreq (ev, conv_id, timestamp, max) ->
        client.getconversation(conv_id, timestamp, max).then (r) ->
            ipcsend 'getconversation:response', r
    , false, (ev, conv_id, timestamp, max) -> conv_id

    ipc.on 'togglefullscreen', ->
      mainWindow.setFullScreen not mainWindow.isFullScreen()

    # bye bye
    ipc.on 'logout', logout

    # propagate these events to the renderer
    require('./ui/events').forEach (n) ->
        client.on n, (e) ->
            ipcsend n, e


    # Emitted when the window is closed.
    mainWindow.on 'closed', ->
        mainWindow = null
