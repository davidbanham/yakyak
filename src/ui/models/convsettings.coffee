entity = require './entity'

module.exports = exp = {
    # Current models are dedicated to 'add conversation' functionality
    # but we plan to make this more generic
    searchedEntities: []
    selectedEntities: []
    initialName: null
    initialSearchQuery: null
    name: ""
    searchQuery: ""
    id: null

    setSearchedEntities: (entities) ->
        @searchedEntities = entities or []
        updated 'searchedentities'

    addSelectedEntity: (entity) ->
        id = entity.id?.chat_id or entity # may pass id directly
        exists = (e for e in @selectedEntities when e.id.chat_id == id).length != 0
        if not exists
            @selectedEntities.push entity
            updated 'selectedEntities'

    removeSelectedEntity: (entity) ->
        id = entity.id?.chat_id or entity # may pass id directly
        @selectedEntities = (e for e in @selectedEntities when e.id.chat_id != id)
        updated 'selectedEntities'

    setSelectedEntities: (entities) -> @selectedEntities = entities or [] # no need to update

    setInitialName: (name) -> @initialName = name
    getInitialName: -> v = @initialName; @initialName = null; v

    setInitialSearchQuery: (query) -> @initialSearchQuery = query
    getInitialSearchQuery: -> v = @initialSearchQuery; @initialSearchQuery = null; v

    setName: (name) -> @name = name

    setSearchQuery: (query) -> @searchQuery = query
    
    loadConversation: (c) ->
        c.participant_data.forEach (p) =>
            id = p.id.chat_id or p.id.gaia_id
            if entity.isSelf id then return
            p = entity[id]
            @selectedEntities.push
                id: chat_id: id
                properties:
                    photo_url: p.photo_url
                    display_name: p.display_name or p.fallback_name
        @id = c.conversation_id?.id or c.id?.id
        @initialName = @name = c.name or ""
        @initialSearchQuery = ""
        
        updated 'convsettings'

    reset: ->
        @searchedEntities = []
        @selectedEntities = []
        @initialName = ""
        @initialSearchQuery = ""
        @searchQuery = ""
        @name = ""
        @id = null
        updated 'convsettings'


}

