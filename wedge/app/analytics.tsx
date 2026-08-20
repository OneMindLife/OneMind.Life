import Script from "next/script";

// Analytics parity with the live Flutter app (web/index.html): first-touch
// attribution (visitor_source/gclid/utm → sessionStorage _om_attr), GA4 (gtag),
// PostHog (autocapture + replay), and the window._onemindLogEvent bridge that
// stamps attribution onto every custom event and beacons it to BOTH. Keeping
// the same event names + attribution preserves ad-conversion tracking and the
// tier3 acquisition read after the wedge replaces Flutter on onemind.life.
//
// (Same IDs as the live app so GA4/PostHog history is continuous.)
const ATTR = `(function(){try{var MO='_om_mode';if(!sessionStorage.getItem(MO))sessionStorage.setItem(MO,Math.random()<0.5?'fun':'decision');var K='_om_attr';if(sessionStorage.getItem(K))return;
var qp=new URLSearchParams(location.search||'');
var gclid=qp.get('gclid')||qp.get('gbraid')||qp.get('wbraid')||'';
var gadSrc=qp.get('gad_source')||'';var utmSource=qp.get('utm_source')||'';
var landing=location.pathname||'/';var ref=document.referrer||'';var refHost='';
try{refHost=ref?new URL(ref).hostname.toLowerCase():'';}catch(e){}
var sameSite=refHost&&/(^|\\.)onemind\\.life$/.test(refHost);var source;
var isTg=(window.TelegramWebviewProxy!==undefined)||/tgWebApp/i.test((location.hash||'')+(location.search||''))||refHost==='org.telegram.messenger'||/(^|\\.)t\\.me$/.test(refHost)||utmSource==='telegram';
var fbclid=qp.get('fbclid')||'';
if(isTg)source='telegram';
else if(gclid||gadSrc)source='google_ads';
else if(fbclid||/(^|\\.)(instagram|facebook)\\.com$/.test(refHost)||refHost==='l.instagram.com'||refHost==='m.facebook.com')source='meta_ad';
else if(utmSource)source='utm_'+utmSource;
else if(landing.indexOf('/join')===0||landing.indexOf('/g/')===0)source='invite';
else if(refHost&&!sameSite&&/google\\.|bing\\.|duckduckgo\\.|yahoo\\.|ecosia\\.|search\\./.test(refHost))source='organic_search';
else if(refHost&&!sameSite)source='referral';else source='direct';
sessionStorage.setItem(K,JSON.stringify({visitor_source:source,gclid:gclid?gclid.slice(0,80):'',utm_campaign:qp.get('utm_campaign')||'',utm_term:qp.get('utm_term')||'',utm_content:qp.get('utm_content')||'',landing_path:landing,referrer_host:refHost}));}catch(e){}})();`;

const BRIDGE = `
window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments);}
gtag('js',new Date());gtag('config','G-BMGWEGECWY');
!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="capture identify alias people.set people.set_once set_config register register_once unregister opt_out_capturing has_opted_out_capturing opt_in_capturing reset isFeatureEnabled onFeatureFlags getFeatureFlag getFeatureFlagPayload reloadFeatureFlags group updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures getActiveMatchingSurveys getSurveys getNextSurveyStep onSessionId".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
posthog.init('phc_CZ6p4kscxuBJVB33j29ccRYNwKraezDuN6C5h2ifYiTa',{api_host:'https://us.i.posthog.com',person_profiles:'always'});
window._onemindLogEvent=function(name,paramsJson){var params={};try{var parsed=paramsJson?JSON.parse(paramsJson):{};for(var k in parsed)if(Object.prototype.hasOwnProperty.call(parsed,k))params[k]=parsed[k];}catch(e){}
try{var a=JSON.parse(sessionStorage.getItem('_om_attr')||'{}');if(params.visitor_source===undefined&&a.visitor_source)params.visitor_source=a.visitor_source;if(params.landing_path===undefined&&a.landing_path)params.landing_path=a.landing_path;if(params.utm_campaign===undefined&&a.utm_campaign)params.utm_campaign=a.utm_campaign;if(params.utm_term===undefined&&a.utm_term)params.utm_term=a.utm_term;if(params.gclid===undefined&&a.gclid)params.gclid=a.gclid;}catch(e){}
try{var mo=sessionStorage.getItem('_om_mode');if(mo&&params.play_mode===undefined)params.play_mode=mo;}catch(e){}
try{if(window.posthog&&window.posthog.capture)window.posthog.capture(name,params,{transport:'sendBeacon'});}catch(e){}
if(typeof gtag==='function'){var gp={transport_type:'beacon'};for(var k2 in params)if(Object.prototype.hasOwnProperty.call(params,k2))gp[k2]=params[k2];gtag('event',name,gp);}};`;

export function Analytics() {
  return (
    <>
      <Script id="om-attr" strategy="beforeInteractive">
        {ATTR}
      </Script>
      <Script
        src="https://www.googletagmanager.com/gtag/js?id=G-BMGWEGECWY"
        strategy="afterInteractive"
      />
      <Script id="om-bridge" strategy="afterInteractive">
        {BRIDGE}
      </Script>
    </>
  );
}
