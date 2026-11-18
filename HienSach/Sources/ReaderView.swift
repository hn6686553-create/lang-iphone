import SwiftUI
private enum ReaderPanel:String,Identifiable{case contents,appearance;var id:Self{self}}
struct ReaderView:View {
    @EnvironmentObject var shelf:Shelf
    @Environment(\.dismiss) var dismiss
    let book:Book
    @State private var spot:ReadingSpot
    @State private var request:PageRequest
    @State private var page=1
    @State private var pages=1
    @State private var panel:ReaderPanel?
    @State private var failure:String?
    @State private var showEnd=false
    @State private var beginning=false
    init(book:Book,start:ReadingSpot){
        self.book=book;_spot=State(initialValue:start);_request=State(initialValue:PageRequest(action:.jump(start)))
    }
    private var options:ReaderOptions{shelf.options}
    private var foreground:Color{Color(bookHex:options.paper.ink)}
    private var background:Color{Color(bookHex:options.paper.background)}
    private var exists:Bool{shelf.book(book.id)?.ribbons.contains{Shelf.matches($0.spot,spot)} ?? false}
    private var currentTitle:String{book.label(at:spot)}
    private func save(_ value:ReadingSpot,_ pageNo:Int,_ count:Int){
        spot=value;page=pageNo;pages=count;shelf.record(book.id,spot:value)
    }
    private func boundary(_ d:Int){
        if d>0{showEnd=true}else{beginning=true;Task{try? await Task.sleep(nanoseconds:1_200_000_000);beginning=false}}
    }
    var body:some View{
        VStack(spacing:0){
            HStack(spacing:2){
                Button{dismiss()}label:{Image(systemName:"chevron.down").frame(width:42,height:43)}.accessibilityLabel("Trở về tủ sách").accessibilityIdentifier("closeReader")
                VStack(alignment:.leading,spacing:2){
                    Text(book.title).font(.system(size:17,weight:.semibold,design:.serif)).lineLimit(1)
                    if !book.author.isEmpty{Text(book.author).font(.caption2).opacity(0.75).lineLimit(1)}
                }.frame(maxWidth:.infinity,alignment:.leading)
                Button{panel = .contents}label:{Image(systemName:"list.bullet").frame(width:38,height:43)}.accessibilityLabel("Mục lục").accessibilityIdentifier("contents")
                Button{shelf.toggleRibbon(book.id,spot:spot)}label:{Image(systemName:exists ? "bookmark.fill":"bookmark").frame(width:38,height:43)}.accessibilityLabel(exists ? "Bỏ dấu trang":"Đặt dấu trang").accessibilityIdentifier("ribbon")
                Button{panel = .appearance}label:{Text("Aa").font(.system(size:20,design:.serif)).frame(width:40,height:43)}.accessibilityLabel("Tùy chỉnh cách đọc").accessibilityIdentifier("appearance")
            }.padding(.horizontal,6).padding(.vertical,3)
            Divider()
            if let failure{
                ContentUnavailableView("Chưa mở được trang",systemImage:"book.closed",description:Text(failure)).frame(maxHeight:.infinity)
            }else if book.kind == .pdf{
                FixedPages(url:shelf.folder(book.id).appendingPathComponent("document.pdf"),options:options,request:request,changed:save,ended:boundary)
                    .modifier(PDFPaper(paper:options.paper))
            }else{
                TextPages(book:book,root:shelf.folder(book.id).appendingPathComponent("content",isDirectory:true),options:options,request:request,changed:save,ended:boundary,failed:{failure=$0})
            }
            Divider()
            HStack{
                Button{request=PageRequest(action:.step(-1))}label:{Image(systemName:"chevron.left").frame(width:48,height:44)}.accessibilityLabel("Trang trước").accessibilityIdentifier("prev")
                Spacer()
                VStack(spacing:2){
                    if book.kind != .pdf{Text(beginning ? "Đầu sách":currentTitle).font(.caption).lineLimit(1).accessibilityIdentifier("chapterName")}
                    Text(book.kind == .pdf ? "Trang \(page) / \(book.units)" : "\(page) / \(pages)  ·  Chương \(spot.unit+1) / \(book.units)").font(.caption2.monospacedDigit()).opacity(0.76).accessibilityIdentifier("pageState")
                }.accessibilityElement(children:.contain)
                Spacer()
                Button{request=PageRequest(action:.step(1))}label:{Image(systemName:"chevron.right").frame(width:48,height:44)}.accessibilityLabel("Trang sau").accessibilityIdentifier("next")
            }.padding(.horizontal,8).padding(.vertical,2)
        }.foregroundStyle(foreground).tint(foreground).background(background.ignoresSafeArea())
        .preferredColorScheme(options.paper == .night ? .dark:.light)
        .sheet(item:$panel){ item in
            if item == .appearance{ReadingSettings(isPDF:book.kind == .pdf).environmentObject(shelf)}
            else{ContentsPanel(book:shelf.book(book.id) ?? book,folder:shelf.folder(book.id),current:spot,choose:{value in panel=nil;request=PageRequest(action:.jump(value))})}
        }
        .confirmationDialog("Bạn đã tới cuối sách",isPresented:$showEnd,titleVisibility:.visible){
            Button("Đánh dấu đã đọc"){shelf.finish(book.id,true);dismiss()};Button("Đọc tiếp ở đây",role:.cancel){}
        }
        .onDisappear{shelf.flush()}
    }
}
private struct PDFPaper:ViewModifier{
    let paper:Paper
    @ViewBuilder func body(content:Content)->some View{
        content.overlay { Color.white.blendMode(.difference).opacity(paper == .night ? 1:0).allowsHitTesting(false).accessibilityHidden(true) }
            .compositingGroup().colorMultiply(Color(bookHex:paper == .night ? "#E3DAC7":paper.background))
    }
}
private struct ContentsPanel:View {
    @Environment(\.dismiss) var dismiss
    let book:Book
    let folder:URL
    let current:ReadingSpot
    let choose:(ReadingSpot)->Void
    @State private var pageJump=""
    @State private var query=""
    @State private var results:[Passage]=[]
    @State private var finding=false
    var body:some View{
        NavigationStack{
            List{
                if query.clean.count>=2 {
                    Section("Kết quả trong sách"){
                        if finding{ProgressView("Đang tìm…")}
                        else if results.isEmpty{Text("Không tìm thấy đoạn có cụm từ này.").foregroundStyle(.secondary)}
                        ForEach(results){r in
                            Button{choose(.init(unit:r.unit,findText:r.query))}label:{
                                VStack(alignment:.leading,spacing:4){Text(r.title).font(.headline);Text(r.excerpt).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)}
                            }
                        }
                    }
                }
                if book.kind == .pdf{
                    HStack{
                        TextField("Trang 1–\(book.units)",text:$pageJump).keyboardType(.numberPad).accessibilityIdentifier("pageNumber")
                        Button("Đi tới"){if let n=Int(pageJump),(1...book.units).contains(n){choose(.init(unit:n-1))}}.disabled(!(1...book.units).contains(Int(pageJump) ?? 0))
                    }
                }
                if query.clean.count<2 && !book.contents.isEmpty{
                    Section("Trong cuốn sách"){
                        ForEach(Array(book.contents.enumerated()),id:\.offset){_,entry in
                            Button{choose(entry.spot)}label:{
                                HStack{Text(entry.title);Spacer();if entry.spot.unit==current.unit{Image(systemName:"circle.fill").font(.system(size:6))}}
                            }
                        }
                    }
                }
                if !book.ribbons.isEmpty{Section("Dấu trang"){ForEach(book.ribbons){m in Button{choose(m.spot)}label:{Label(m.label,systemImage:"bookmark")}}}}
            }.searchable(text:$query,placement:.navigationBarDrawer(displayMode:.always),prompt:"Tìm chữ trong sách")
                .task(id:query){
                    results=[];let term=query.clean
                    guard term.count>=2 else{finding=false;return};finding=true
                    do{
                        try await Task.sleep(nanoseconds:300_000_000)
                        let b=book, f=folder
                        let job=Task.detached(priority:.userInitiated){try FindInBook.passages(in:b,folder:f,query:term)}
                        let found=try await withTaskCancellationHandler(operation:{try await job.value},onCancel:{job.cancel()})
                        try Task.checkCancellation();results=found;finding=false
                    }catch{if !Task.isCancelled{finding=false}}
                }.navigationTitle("Mục lục").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.confirmationAction){Button("Xong"){dismiss()}}}
        }.presentationDetents([.medium,.large])
    }
}
private struct ReadingSettings:View{
    @EnvironmentObject var shelf:Shelf
    @Environment(\.dismiss) var dismiss
    let isPDF:Bool
    var body:some View{
        NavigationStack{
            Form{
                Section("Màu giấy"){
                    HStack(spacing:8){ForEach(Paper.allCases){p in
                        Button{shelf.options.paper=p}label:{
                            VStack(spacing:6){
                                Text("Aa").font(.system(size:23,design:.serif)).foregroundStyle(Color(bookHex:p.ink)).frame(maxWidth:.infinity,minHeight:42)
                                    .background(Color(bookHex:p.background),in:RoundedRectangle(cornerRadius:7)).overlay{RoundedRectangle(cornerRadius:7).strokeBorder(shelf.options.paper == p ? Color.accentColor:Color.secondary.opacity(0.25),lineWidth:shelf.options.paper == p ? 2:1)}
                                Text(p.title).font(.caption2).foregroundStyle(.primary)
                            }
                        }.buttonStyle(.plain).accessibilityLabel(p.title).accessibilityAddTraits(shelf.options.paper == p ? [.isSelected]:[])
                    }}
                }
                if !isPDF{
                    Section("Chữ và khoảng cách"){
                        Picker("Phông chữ",selection:$shelf.options.typeface){ForEach(Typeface.allCases){Text($0.rawValue).tag($0)}}
                        Stepper("Cỡ chữ · \(Int(shelf.options.size))",value:$shelf.options.size,in:14...34,step:1)
                        Stepper("Giãn dòng · \(shelf.options.leading,specifier:"%.2f")",value:$shelf.options.leading,in:1.25...2.05,step:0.1)
                        Stepper("Lề trang · \(Int(shelf.options.margin))",value:$shelf.options.margin,in:12...48,step:2)
                    }
                }
                Section{
                    Picker("Cách chuyển trang",selection:$shelf.options.paged){Text("Lật trang").tag(true);Text("Cuộn dọc").tag(false)}
                    if shelf.options.paged{Toggle("Hiệu ứng lật giấy",isOn:$shelf.options.curled)}
                }footer:{if isPDF{Text("Chụm hoặc mở hai ngón tay để thu phóng trang PDF.")}}
            }.navigationTitle("Tùy chỉnh cách đọc").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.confirmationAction){Button("Xong"){dismiss()}.accessibilityIdentifier("doneSettings")}}
        }.presentationDetents([.large]).tint(Palette.green)
    }
}
