{nameof} = require '../util'

module.exports = view (models) ->
    {conv, entity, viewstate} = models
    div class:'convlist', ->
        conv.list().forEach (c) ->
            cid = c?.conversation_id?.id
            ur = conv.unread c
            clz = ['conv']
            clz.push "type_#{c.type}"
            clz.push "selected" if models.viewstate.selectedConv == cid
            clz.push "unread" if ur
            div key:cid, class:clz.join(' '), ->
                part = c?.current_participant ? []
                ents = for p in part when not entity.isSelf p.chat_id
                    entity[p.chat_id]
                name = if c.name?
                    c.name
                else
                    # all entities in conversation that is not self
                    # the names of those entities
                    names = ents.map nameof
                    # joined together in a compelling manner
                    names.join ', '
                div class: 'thumbs', ->
                    for p, index in ents
                        if index >= 2 then continue
                        if not p.photo_url then entity.needEntity p.id
                        image = 'http:' + p.photo_url
                        if not p.photo_url then image = "images/photo.jpg"
                        img src: image
                span class:'convname', name
                if ur > 0 and not conv.isQuiet(c)
                    lbl = if ur >= conv.MAX_UNREAD then "#{conv.MAX_UNREAD}+" else ur + ''
                    span class:'unreadcount', lbl
            , onclick: (ev) ->
                ev.preventDefault()
                action 'selectConv', c
