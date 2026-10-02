/* Native Android/iOS uses Mapbox Flutter. This bridge owns web map lifecycle. */
(() => {
  const entries = new Map();
  function render(entry) {
    const {vehicles, route, destination, pitch, traffic} = entry.options;
    const ids = new Set(vehicles.map(v => v.id));
    for (const [id, marker] of entry.markers) {
      if (!ids.has(id)) { marker.remove(); entry.markers.delete(id); }
    }
    for (const vehicle of vehicles) {
      let marker = entry.markers.get(vehicle.id);
      if (!marker) {
        const button = document.createElement('button');
        button.className = 'revtrack-marker'; button.type = 'button';
        button.setAttribute('aria-label', `Pilih ${vehicle.plate}`);
        const icon = document.createElement('span'); icon.textContent = vehicle.ev ? 'ϟ' : '↗'; button.append(icon);
        button.addEventListener('click', () => entry.callback(vehicle.id));
        marker = new mapboxgl.Marker({element:button}).setLngLat([vehicle.longitude,vehicle.latitude]).addTo(entry.map);
        entry.markers.set(vehicle.id, marker);
      }
      marker.setLngLat([vehicle.longitude,vehicle.latitude]);
      marker.getElement().classList.toggle('selected', vehicle.id === entry.selected);
      marker.getElement().classList.toggle('offline', vehicle.status === 'offline');
      marker.getElement().title = `${vehicle.plate} · telemetri simulasi`;
    }
    if (!entry.map.isStyleLoaded()) return;
    const geometry = route.length >= 2
      ? {type:'Feature',properties:{},geometry:{type:'LineString',coordinates:route}}
      : {type:'FeatureCollection',features:[]};
    if (!entry.map.getSource('revtrack-route')) {
      entry.map.addSource('revtrack-route',{type:'geojson',data:geometry});
      entry.map.addLayer({id:'revtrack-route-casing',type:'line',source:'revtrack-route',layout:{'line-cap':'round','line-join':'round'},paint:{'line-color':'#ffffff','line-width':9}});
      entry.map.addLayer({id:'revtrack-route-line',type:'line',source:'revtrack-route',layout:{'line-cap':'round','line-join':'round'},paint:{'line-color':'#1764ee','line-width':5}});
    } else entry.map.getSource('revtrack-route').setData(geometry);
    if (destination) {
      if (!entry.destinationMarker) entry.destinationMarker = new mapboxgl.Marker({color:'#14243d'}).setLngLat(destination).addTo(entry.map);
      else entry.destinationMarker.setLngLat(destination);
    } else { entry.destinationMarker?.remove(); entry.destinationMarker = null; }
    if (traffic && !entry.map.getSource('revtrack-traffic-source')) {
      entry.map.addSource('revtrack-traffic-source',{type:'vector',url:'mapbox://mapbox.mapbox-traffic-v1'});
    }
    if (traffic && !entry.map.getLayer('revtrack-traffic')) {
      entry.map.addLayer({id:'revtrack-traffic',type:'line',source:'revtrack-traffic-source','source-layer':'traffic',paint:{'line-width':2,'line-opacity':.75,'line-color':['match',['get','congestion'],'low','#51b88a','moderate','#f4b447','heavy','#ea7657','severe','#c7445b','#9ab4ce']}});
    } else if (!traffic && entry.map.getLayer('revtrack-traffic')) entry.map.removeLayer('revtrack-traffic');
    if (entry.lastPitch !== pitch) { entry.map.easeTo({pitch,duration:entry.reduceMotion ? 0 : 450}); entry.lastPitch = pitch; }
    if (entry.pendingFocus) {
      entry.pendingFocus = false;
      if (route.length >= 2) {
        const bounds = route.reduce((b,p)=>b.extend(p),new mapboxgl.LngLatBounds(route[0],route[0]));
        entry.map.fitBounds(bounds,{padding:{top:160,right:55,bottom:260,left:55},maxZoom:14,duration:entry.reduceMotion ? 0 : 700});
      } else {
        const vehicle = vehicles.find(v=>v.id === entry.selected);
        if (vehicle) entry.map.flyTo({center:[vehicle.longitude,vehicle.latitude],zoom:13,pitch,duration:entry.reduceMotion ? 0 : 650});
      }
    }
  }
  window.revtrackCreateMap = (id,token,style,raw,selected,callback) => {
    const options = JSON.parse(raw);
    const entry = {markers:new Map(),options,callback,selected,disposed:false,attempts:0,reduceMotion:false,lastPitch:options.pitch};
    entries.set(id,entry);
    const mount = () => {
      if (entry.disposed) return;
      const host = document.getElementById(id);
      if (!host?.isConnected) { if (++entry.attempts < 120) requestAnimationFrame(mount); return; }
      if (!window.mapboxgl) { host.textContent = 'Mapbox belum dimuat. Periksa koneksi lalu muat ulang.'; return; }
      const note = document.createElement('div'); note.className = 'revtrack-map-loading'; note.textContent = 'Memuat peta Mapbox…'; host.append(note); entry.note = note;
      try {
        entry.map = new mapboxgl.Map({container:host,accessToken:token,style,center:[106.821,-6.214],zoom:11.4,pitch:options.pitch,attributionControl:true});
        entry.map.addControl(new mapboxgl.NavigationControl({showCompass:true}),'top-right');
        entry.map.addControl(new mapboxgl.ScaleControl({maxWidth:80}),'bottom-left');
        entry.map.on('style.load',()=>{
          try { entry.map.setConfigProperty('basemap','lightPreset','day'); } catch (_) { /* custom styles may omit Standard import */ }
          note.remove();
          render(entry);
        });
        entry.map.on('error',()=>{
          note.className = 'revtrack-map-error';
          note.textContent = 'Peta gagal dimuat. Periksa koneksi, token, dan akses style Mapbox.';
          if (!note.isConnected) host.append(note);
        });
        entry.resize = new ResizeObserver(()=>entry.map.resize()); entry.resize.observe(host);
        render(entry);
      } catch (_) { note.className = 'revtrack-map-error'; note.textContent = 'Mapbox tidak dapat dimulai pada browser ini.'; }
    };
    requestAnimationFrame(mount);
  };
  window.revtrackUpdateMap = (id,raw,selected,reduceMotion) => {
    const entry = entries.get(id); if (!entry || entry.disposed) return;
    const options = JSON.parse(raw);
    entry.pendingFocus = entry.pendingFocus || entry.selected !== selected || entry.options.focusSerial !== options.focusSerial;
    const styleChanged = entry.options.style !== options.style;
    entry.options = options; entry.selected = selected; entry.reduceMotion = reduceMotion;
    if (!entry.map) return;
    if (styleChanged) entry.map.setStyle(options.style);
    render(entry);
  };
  window.revtrackDestroyMap = id => {
    const entry = entries.get(id); if (!entry) return;
    entry.disposed = true; entry.resize?.disconnect(); entry.map?.remove(); entries.delete(id);
  };
})();
