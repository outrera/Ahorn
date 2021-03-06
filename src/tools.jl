include("brush.jl")

loadedTools = joinpath.(abs"tools", readdir(abs"tools"))
loadModule.(loadedTools)
currentTool = nothing

function getToolName(tool::String)
    if hasModuleField(tool, "displayName")
        return getModuleField(tool, "displayName")

    elseif haskey(loadedModules, tool)
        return repr(loadedModules[tool])
    end
end

function getToolGroup(tool::String)
    if hasModuleField(tool, "group")
        return getModuleField(tool, "group")

    elseif haskey(loadedModules, tool)
        return "Unknown"
    end
end

toolDisplayNames = Dict{String, String}()
function updateToolDisplayNames!(tools::Array{String, 1})
    global toolDisplayNames = Dict{String, String}(
        getToolName(tool) => tool for tool in loadedTools if haskey(loadedModules, tool)
    )
end

subtoolList = generateTreeView("Mode", [], sortable=false)
connectChanged(subtoolList, function(list::ListContainer, selected::String)
    eventToModule(currentTool, "subToolSelected", list, selected)
end)

layersList = generateTreeView(("Layer", "Visible"), Tuple{String, Bool}[], sortable=false)
connectChanged(layersList, function(list::ListContainer, selected::String, visible::Bool)
    eventToModule(currentTool, "layerSelected", list, selected)
    eventToModule(currentTool, "layerSelected", list, selected, visible)
    eventToModule(currentTool, "layerSelected", list, materialList, selected)
    eventToModule(currentTool, "layerSelected", list, materialList, selected, visible)
end)
connectDoubleClick(layersList, function(list::ListContainer, selected::String, visible::Bool)
    dr = getDrawableRoom(loadedState.map, loadedState.room)
    layer = getLayerByName(dr.layers, selected)
    layer.visible = !visible
    dr.rendering.redraw = true

    names = String[row[1] for row in getListData(layersList)]
    updateLayerList!(names, row -> row[1] == selected)
    draw(canvas)
end)

materialList = generateTreeView("Material", [], sortable=false)
connectChanged(materialList, function(list::ListContainer, selected::String)
    eventToModule(currentTool, "materialSelected", list, selected)
end)

function changeTool!(tool::String)
    if loadedState.map !== nothing && loadedState.room !== nothing
        dr = getDrawableRoom(loadedState.map, loadedState.room)

        if currentTool !== nothing
            eventToModule(currentTool, "cleanup")
        end

        if tool in loadedTools
            global currentTool = tool
        
        elseif haskey(toolDisplayNames, tool)
            global currentTool = toolDisplayNames[tool]
        end
        
        # Clear the subtool and material list
        # Tools need to set up this themselves
        updateTreeView!(subtoolList, [])
        updateTreeView!(materialList, [])

        eventToModule(currentTool, "layersChanged", dr.layers)
        eventToModule(currentTool, "toolSelected")
        eventToModule(currentTool, "toolSelected", subtoolList, layersList, materialList)
    end
end

function getSortedToolNames(tools::Array{String, 1})
    res = Tuple{String, String}[]
    for tool in tools
        group, name = getToolGroup(tool), getToolName(tool)
        
        if group !== nothing && name !== nothing
            push!(res, (group, name))
        end
    end
    
    sort!(res)

    return String[r[2] for r in res]
end

toolList = generateTreeView("Tool", String[], sortable=false)
connectChanged(toolList, function(list::ListContainer, selected::String)
    debug.log("Selected $selected", "TOOLS_SELECTED")
    changeTool!(selected)
end)

function updateToolList!(list::ListContainer)
    updateTreeView!(list, getSortedToolNames(loadedTools), 1)
end

function selectionRectangle(x1::Number, y1::Number, x2::Number, y2::Number)
    drawX = min(x1, x2)
    drawW = abs(x1 - x2) + 1

    drawY = min(y1, y2)
    drawH = abs(y1 - y2) + 1

    return Rectangle(drawX, drawY, drawW, drawH)
end

function updateSelectionByCoords!(map::Map, ax::Number, ay::Number)
    room = Maple.getRoomByCoords(map, ax, ay)

    if room != false && room.name != loadedState.roomName
        select!(roomList, row -> row[1] == room.name)
    
        return true
    end

    return false
end

function selectMaterialList!(m::String)
    select!(materialList, row -> row[1] == m)
end

function setMaterialList!(materials::Array{String, 1}, selector::Union{Function, Integer, Void}=nothing)
    Gtk.GLib.@sigatom setproperty!(materialFilterEntry, :text, "")

    if selector !== nothing
        updateTreeView!(materialList, materials, selector)
    
    else
        updateTreeView!(materialList, materials)
    end
end

function selectLayer!(layers::Array{Layer, 1}, layer::String, default::String="")
    newLayer = getLayerByName(layers, layer, default)
    select!(layersList, row -> row[1] == newLayer.name)

    return newLayer
end

selectLayer!(layers::Array{Layer, 1}, layer::Union{Layer, Void}, default::String="") = selectLayer!(layers, layerName(layer), default)

function updateLayerList!(names::Array{String, 1}, selector::Union{Function, Integer, Void}=nothing)
    data = Tuple{String, Bool}[]
    dr = getDrawableRoom(loadedState.map, loadedState.room)

    for name in names
        layer = getLayerByName(dr.layers, name)
        push!(data, (name, layer.visible || layer.dummy))
    end

    if selector !== nothing
        updateTreeView!(layersList, data, selector)
    
    else
        updateTreeView!(layersList, data)
    end
end

function handleSelectionMotion(start::eventMouse, startCamera::Camera, current::eventMouse)
    room = loadedState.room
    
    mx1, my1 = getMapCoordinates(startCamera, start.x, start.y)
    mx2, my2 = getMapCoordinates(camera, current.x, current.y)

    max1, may1 = getMapCoordinatesAbs(startCamera, start.x, start.y)
    max2, may2 = getMapCoordinatesAbs(camera, current.x, current.y)

    x1, y1 = mapToRoomCoordinates(mx1, my1, room)
    x2, y2 = mapToRoomCoordinates(mx2, my2, room)

    ax1, ay1 = mapToRoomCoordinatesAbs(max1, may1, room)
    ax2, ay2 = mapToRoomCoordinatesAbs(max2, may2, room)

    # Grid Based coordinates
    eventToModule(currentTool, "selectionMotion", selectionRectangle(x1, y1, x2, y2))
    eventToModule(currentTool, "selectionMotion", x1, y1, x2, y2)

    # Absolute coordinates
    eventToModule(currentTool, "selectionMotionAbs", selectionRectangle(ax1, ay1, ax2, ay2))
    eventToModule(currentTool, "selectionMotionAbs", ax1, ay1, ax2, ay2)
end

function handleSelectionFinish(start::eventMouse, startCamera::Camera, current::eventMouse, currentCamera::Camera)
    room = loadedState.room
    
    mx1, my1 = getMapCoordinates(startCamera, start.x, start.y)
    mx2, my2 = getMapCoordinates(currentCamera, current.x, current.y)

    max1, may1 = getMapCoordinatesAbs(startCamera, start.x, start.y)
    max2, may2 = getMapCoordinatesAbs(currentCamera, current.x, current.y)

    x1, y1 = mapToRoomCoordinates(mx1, my1, room)
    x2, y2 = mapToRoomCoordinates(mx2, my2, room)

    ax1, ay1 = mapToRoomCoordinatesAbs(max1, may1, room)
    ax2, ay2 = mapToRoomCoordinatesAbs(max2, may2, room)

    # Grid Based coordinates
    eventToModule(currentTool, "selectionFinish", selectionRectangle(x1, y1, x2, y2))
    eventToModule(currentTool, "selectionFinish", x1, y1, x2, y2)

    # Absolute coordinates
    eventToModule(currentTool, "selectionFinishAbs", selectionRectangle(ax1, ay1, ax2, ay2))
    eventToModule(currentTool, "selectionFinishAbs", ax1, ay1, ax2, ay2)
end

function getMouseEventName(event::eventMouse, downEvent::eventMouse)
    prefix = get(mouseTypePrefix, downEvent.event_type, "")
    handle = mouseHandlers[event.button]

    if !isempty(prefix)
        return prefix * titlecase(handle)
    
    else
        return handle
    end
end

function handleClicks(event::eventMouse, camera::Camera, downEvent::eventMouse)
    if haskey(mouseHandlers, event.button)
        handle = getMouseEventName(event, downEvent)
        room = loadedState.room

        mx, my = getMapCoordinates(camera, event.x, event.y)
        max, may = getMapCoordinatesAbs(camera, event.x, event.y)

        x, y = mapToRoomCoordinates(mx, my, room)
        ax, ay = mapToRoomCoordinatesAbs(max, may, room)

        lock!(camera)
        if !updateSelectionByCoords!(loadedState.map, max, may)
            # Teleport to cursor 
            if EverestRcon.loaded && event.button == 0x1 && modifierControl() && modifierAlt()
                url = get(config, "everest_rcon", "http://localhost:32270")
                room = loadedState.roomName
                EverestRcon.reload(url, room)
                EverestRcon.teleportToRoom(url, room, ax, ay)

            else
                eventToModule(currentTool, handle)
                eventToModule(currentTool, handle, event, camera)
                eventToModule(currentTool, handle, x, y)
                eventToModule(currentTool, handle * "Abs", ax, ay)
            end
        end
        unlock!(camera)
    end
end

function handleMotion(event::eventMouse, camera::Camera)
    room = loadedState.room

    mx, my = getMapCoordinates(camera, event.x, event.y)
    max, may = getMapCoordinatesAbs(camera, event.x, event.y)

    x, y = mapToRoomCoordinates(mx, my, room)
    ax, ay = mapToRoomCoordinatesAbs(max, may, room)

    eventToModule(currentTool, "mouseMotion", event, camera)
    eventToModule(currentTool, "mouseMotion", x, y)
    eventToModule(currentTool, "mouseMotionAbs", event, camera)
    eventToModule(currentTool, "mouseMotionAbs", ax, ay)
end

function handleRoomModifications(event::eventKey)
    if modifierAlt() && loadedState.room !== nothing && loadedState.map !== nothing
        if haskey(moveDirections, event.keyval)
            History.addSnapshot!(History.RoomSnapshot("Room Movement", loadedState.room))

            ox, oy = moveDirections[event.keyval] .* 8
            loadedState.room.position = loadedState.room.position .+ (ox, oy)
            updateTreeView!(roomList, getTreeData(loadedState.map), row -> row[1] == loadedState.room.name)

            draw(canvas)

            return true

        elseif event.keyval == Gtk.GdkKeySyms.Delete
            index = findfirst(loadedState.map.rooms, loadedState.room)

            if index != 0 && ask_dialog("Are you sure you want to delete this room? '$(loadedState.room.name)'", window)
                History.addSnapshot!(History.MapSnapshot("Room Deletion", loadedState.map))

                deleteat!(loadedState.map.rooms, index)
                updateTreeView!(roomList, getTreeData(loadedState.map))
                draw(canvas)
            end
        end
    end

    return false
end

debugKeys = Dict{Number, Tuple{String, Function}}(
    Gtk.GdkKeySyms.F1 => ("Reloading tools", debug.reloadTools!),
    Gtk.GdkKeySyms.F2 => ("Reloading entities and triggers", () -> debug.reloadEntities!() && debug.reloadTriggers!()),
    Gtk.GdkKeySyms.F3 => ("Deleting room render caches", debug.clearMapDrawingCache!),
)

function handleDebugKeys(event::eventKey)
    if get(debug.config, "ENABLE_HOTSWAP_HOTKEYS", false)
        if haskey(debugKeys, event.keyval)
            desc, func = debugKeys[event.keyval]
            println("! $desc")

            return func()
        end
    end

    return false
end

function handleHotkeyToolChange(event::eventKey)
    if modifierControl() 
        if Int('0') <= event.keyval <= Int('9')
            index = event.keyval == Int('0')? 10 : event.keyval - Int('0')

            sortedToolNames = getSortedToolNames(loadedTools)
            if length(sortedToolNames) >= index
                changeTool!(sortedToolNames[index])
                select!(toolList, index)

                return true
            end
        end

        return false
    end

    return false
end

function handleKeyPressed(event::eventKey)
    # Handle in this order, until one of them consumes the event
    return handleDebugKeys(event) ||
        handleRoomModifications(event) ||
        handleHotkeyToolChange(event) ||
        eventToModule(currentTool, "keyboard", event)
end

function handleKeyReleased(event::eventKey)

end

function handleRoomChanged(map::Map, room::Room)
    dr = getDrawableRoom(map, room)

    # Clean up tools layer before notifying about room change
    eventToModule(currentTool, "cleanup")

    eventToModule(currentTool, "roomChanged", room)
    eventToModule(currentTool, "roomChanged", map, room)
    eventToModule(currentTool, "layersChanged", dr.layers)

    # Update visibility col
    names = String[row[1] for row in getListData(layersList)]
    updateLayerList!(names)
end