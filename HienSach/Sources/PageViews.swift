import SwiftUI
import WebKit
import PDFKit

struct PageRequest: Equatable {
    enum Action: Equatable { case jump(ReadingSpot), step(Int) }
    let id = UUID()
    let action: Action
}
private let readerWorld = WKContentWorld.defaultClient
private let readerScript = (try? Bundle.main.url(forResource:"reader",withExtension:"js").map { try String(contentsOf:$0,encoding:.utf8) }) ?? ""
private func locationData(_ spot: ReadingSpot) -> [String:Any] {
    var data:[String:Any] = ["fraction":spot.fraction]
    if let fragment=spot.fragment { data["fragment"]=fragment }
    if let text=spot.findText { data["findText"]=text }
    if let p=spot.paragraph { data["paragraph"]=p }
    return data
}
private func turnAnimation(_ view:UIView, _ d:Int) {
    guard !UIAccessibility.isReduceMotionEnabled, view.window != nil,view.bounds.height>30 else { return }
    let overlayTag=903721
    view.viewWithTag(overlayTag)?.removeFromSuperview()
    guard let snapshot=view.snapshotView(afterScreenUpdates:false) else{return}
    let carrier=UIView()
    carrier.tag=overlayTag;carrier.isUserInteractionEnabled=false;carrier.accessibilityElementsHidden=true
    // Rotate the curl axis to turn across the spread; the contents remain upright.
    carrier.bounds=CGRect(origin:.zero,size:CGSize(width:view.bounds.height,height:view.bounds.width))
    carrier.center=CGPoint(x:view.bounds.midX,y:view.bounds.midY)
    carrier.transform=CGAffineTransform(rotationAngle:.pi/2)
    snapshot.bounds=view.bounds;snapshot.center=CGPoint(x:carrier.bounds.midX,y:carrier.bounds.midY)
    snapshot.transform=CGAffineTransform(rotationAngle: -.pi/2)
    carrier.addSubview(snapshot);view.addSubview(carrier)
    let curl:UIView.AnimationOptions=d>0 ? .transitionCurlUp:.transitionCurlDown
    UIView.transition(with:carrier,duration:0.40,options:[curl,.showHideTransitionViews,.allowUserInteraction],animations:{
        snapshot.isHidden=true
    },completion:{_ in carrier.removeFromSuperview()})
}

struct TextPages: UIViewRepresentable {
    let book:Book
    let root:URL
    let options:ReaderOptions
    let request:PageRequest
    let changed:(ReadingSpot,Int,Int)->Void
    let ended:(Int)->Void
    let failed:(String)->Void
    func makeCoordinator()->Coordinator { Coordinator(self) }
    func makeUIView(context:Context)->WKWebView {
        let c=WKWebViewConfiguration(); c.websiteDataStore = .nonPersistent(); c.defaultWebpagePreferences.allowsContentJavaScript=false
        c.userContentController.addUserScript(WKUserScript(source:readerScript,injectionTime:.atDocumentEnd,forMainFrameOnly:true,in:readerWorld))
        c.userContentController.add(context.coordinator,contentWorld:readerWorld,name:"page")
        let view=WKWebView(frame:.zero,configuration:c);view.navigationDelegate=context.coordinator
        view.isOpaque=false;view.backgroundColor = .clear;view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled=false;view.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.view=view
        let rules = #"[{"trigger":{"url-filter":".*","resource-type":["script","media","popup"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier:"HienSachOffline1",encodedContentRuleList:rules) { [weak view, weak co=context.coordinator] rule,_ in
            guard let view,let co else{return}
            guard let rule else{co.owner.failed("Chưa chuẩn bị được trình đọc. Hãy đóng sách và thử lại.");return}
            view.configuration.userContentController.add(rule);co.allowed=true;co.update()
        }
        return view
    }
    func updateUIView(_ view:WKWebView,context:Context) { context.coordinator.owner=self;context.coordinator.update() }
    static func dismantleUIView(_ view:WKWebView, coordinator:Coordinator){
        view.navigationDelegate=nil;view.configuration.userContentController.removeScriptMessageHandler(forName:"page",contentWorld:readerWorld);view.stopLoading()
    }
    final class Coordinator:NSObject,WKNavigationDelegate,WKScriptMessageHandler {
        var owner:TextPages
        weak var view:WKWebView?
        var allowed=false,ready=false
        var unit = -1, spot=ReadingSpot(), currentNavigation:WKNavigation?
        var handled:UUID?, appearance:ReaderOptions?
        init(_ owner:TextPages){self.owner=owner}
        func update(){
            guard allowed,view != nil else{return}
            if handled != owner.request.id {
                handled=owner.request.id
                switch owner.request.action {
                case .jump(let dest): jump(dest)
                case .step(let d): step(d)
                }
            }
            if ready,appearance != owner.options { configure() }
        }
        func jump(_ dest:ReadingSpot){
            guard let view,owner.book.chapters.indices.contains(dest.unit) else{return}
            if unit != dest.unit {
                ready=false;spot=dest;unit=dest.unit
                let path=owner.root.appendingPathComponent(owner.book.chapters[unit].file)
                currentNavigation=view.loadFileURL(path,allowingReadAccessTo:owner.root)
            } else {
                spot=dest
                if ready { call("window.hienSach.seek(loc)",["loc":locationData(dest)]) }
            }
        }
        func step(_ d:Int) {
            guard ready,let view else{return}
            if owner.options.curled && owner.options.paged {turnAnimation(view,d)}
            call("window.hienSach.step(d)",["d":d])
        }
        func configure(){
            let o=owner.options;appearance=o
            let dictionary:[String:Any]=["bg":o.paper.background,"ink":o.paper.ink,"font":o.typeface.css,"size":o.size,"leading":o.leading,"margin":o.margin,"paged":o.paged]
            call("window.hienSach.configure(opt,loc)",["opt":dictionary,"loc":locationData(spot)])
        }
        func call(_ code:String,_ args:[String:Any]){
            view?.callAsyncJavaScript(code,arguments:args,in:nil,in:readerWorld) { [weak self] result in
                guard case .failure(let error)=result,let self,self.ready else{return}
                self.owner.failed("Chưa hiển thị được trang sách. \(error.localizedDescription)")
            }
        }
        func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){
            guard navigation === currentNavigation else{return};ready=true;configure()
        }
        func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error){
            if (error as NSError).code != NSURLErrorCancelled { owner.failed(error.localizedDescription) }
        }
        func webViewWebContentProcessDidTerminate(_ webView:WKWebView){let saved=spot;unit = -1;jump(saved)}
        func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){
            guard action.targetFrame?.isMainFrame==true,let url=action.request.url,url.isFileURL,
                  url.standardizedFileURL.path.hasPrefix(owner.root.standardizedFileURL.path+"/") else{decisionHandler(.cancel);return}
            if action.navigationType == .linkActivated {
                decisionHandler(.cancel)
                let relative=String(url.standardizedFileURL.path.dropFirst(owner.root.standardizedFileURL.path.count+1))
                if let i=owner.book.chapters.firstIndex(where:{$0.file==relative}){jump(.init(unit:i,fragment:url.fragment?.removingPercentEncoding))}
            } else {decisionHandler(.allow)}
        }
        func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){
            guard ready,message.frameInfo.isMainFrame,let d=message.body as? [String:Any] else{return}
            if let travel=d["step"] as? Int { step(travel);return }
            if let delta=d["boundary"] as? Int {
                let i=unit+delta
                if owner.book.chapters.indices.contains(i){jump(.init(unit:i,fraction:delta>0 ? 0:1))} else {owner.ended(delta)}
                return
            }
            guard let page=d["page"] as? Int,let pages=d["pages"] as? Int,let fraction=d["fraction"] as? Double else{return}
            let p=d["paragraph"] as? Int
            spot=ReadingSpot(unit:unit,fraction:max(0,min(1,fraction)),paragraph:p.flatMap{$0<0 ? nil:$0})
            owner.changed(spot,page,pages)
        }
    }
}

struct FixedPages:UIViewRepresentable {
    let url:URL
    let options:ReaderOptions
    let request:PageRequest
    let changed:(ReadingSpot,Int,Int)->Void
    let ended:(Int)->Void
    func makeCoordinator()->Coordinator{Coordinator(self)}
    func makeUIView(context:Context)->PDFView{
        let view=PDFView();view.displayBox = .cropBox;view.autoScales=true;view.displaysPageBreaks=false
        view.backgroundColor = .clear;context.coordinator.view=view
        view.document=PDFDocument(url:url)
        NotificationCenter.default.addObserver(context.coordinator,selector:#selector(Coordinator.report),name:.PDFViewPageChanged,object:view)
        return view
    }
    func updateUIView(_ view:PDFView,context:Context){
        let co=context.coordinator;co.owner=self
        if co.paged != options.paged {
            let keep=view.currentPage;co.paged=options.paged
            view.displayMode=options.paged ? .singlePage:.singlePageContinuous
            view.displayDirection=options.paged ? .horizontal:.vertical
            view.usePageViewController(options.paged,withViewOptions:nil);view.autoScales=true
            if let keep{view.go(to:keep)}
        }
        guard co.handled != request.id,let doc=view.document else{return}
        co.handled=request.id
        let target:Int
        switch request.action {
        case .jump(let spot):target=spot.unit
        case .step(let d):
            target=(view.currentPage.map{doc.index(for:$0)} ?? 0)+d
            if options.curled && options.paged {turnAnimation(view,d)}
            if !(0..<doc.pageCount).contains(target){DispatchQueue.main.async { ended(d) };return}
        }
        if let page=doc.page(at:target){view.go(to:page);co.report()}
    }
    static func dismantleUIView(_ view:PDFView,coordinator:Coordinator){NotificationCenter.default.removeObserver(coordinator)}
    final class Coordinator:NSObject{
        var owner:FixedPages;weak var view:PDFView?;var handled:UUID?;var paged:Bool?
        init(_ owner:FixedPages){self.owner=owner}
        @objc func report(){
            DispatchQueue.main.async { [weak self] in
                guard let self,let view,let doc=view.document,let page=view.currentPage else{return}
                let i=doc.index(for:page);guard i<doc.pageCount else{return}
                owner.changed(.init(unit:i),i+1,doc.pageCount)
            }
        }
    }
}
