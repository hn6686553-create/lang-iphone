import SwiftUI
import SafariServices

struct WebReadingRoom:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->SFSafariViewController{
        let config=SFSafariViewController.Configuration();config.entersReaderIfAvailable=true
        return SFSafariViewController(url:url,configuration:config)
    }
    func updateUIViewController(_ controller:SFSafariViewController,context:Context){}
}
struct OnlineView:View {
    @EnvironmentObject var shelf:Shelf
    @State private var address=""
    @State private var items:[OnlineBook]=[]
    @State private var catalogError:String?
    @State private var downloadError:String?
    @State private var loadingCatalog=false
    @State private var task:Task<Void,Never>?
    @State private var percentage:Double?
    @State private var browser=false
    @FocusState private var fieldFocused:Bool
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:19){
                Bookplate();ShelfHeader(title:"Trực tuyến")
                VStack(alignment:.leading,spacing:12){
                    Text("Mở sách từ liên kết").font(.system(size:22,weight:.medium,design:.serif))
                    TextField("Dán liên kết EPUB, PDF hoặc TXT",text:$address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).submitLabel(.go)
                        .focused($fieldFocused).onSubmit{fromAddress()}.padding(12).background(Palette.paper,in:RoundedRectangle(cornerRadius:7))
                    Button(action:fromAddress){Label("Tải về và đọc",systemImage:"arrow.down.to.line").fontWeight(.semibold)}.disabled(address.clean.isEmpty || task != nil)
                }.padding(17).background(Color(bookHex:"#E9E1D1"),in:RoundedRectangle(cornerRadius:13))
                if task != nil{
                    HStack{
                        if let percentage{ProgressView(value:percentage);Text("\(Int(percentage*100))%").font(.caption.monospacedDigit())}
                        else{ProgressView();Text("Đang tải sách…").font(.subheadline)}
                        Spacer();Button("Hủy"){task?.cancel()}
                    }
                }
                if let downloadError{Label(downloadError,systemImage:"exclamationmark.circle").font(.subheadline).foregroundStyle(.red)}
                Text("Tuyển tập Hiên Sách").font(.system(size:24,weight:.medium,design:.serif)).padding(.top,6)
                if loadingCatalog{ProgressView("Đang mở danh mục…")}
                if let catalogError{Text(catalogError).font(.subheadline);Button("Tải lại"){Task{await load()}}}
                ForEach(items){item in
                    let saved=shelf.book(item.sha256)
                    Button{
                        if let saved{shelf.open(saved.id)}else{download(OnlineShelf.base.appendingPathComponent(item.file))}
                    }label:{
                        HStack(spacing:14){
                            Image(systemName:"book.closed").font(.title2).frame(width:42,height:55).background(Palette.green,in:RoundedRectangle(cornerRadius:4)).foregroundStyle(Color(bookHex:"#E7CD94"))
                            VStack(alignment:.leading,spacing:5){Text(item.title).font(.system(size:20,weight:.medium,design:.serif));Text(item.note).font(.caption).foregroundStyle(Palette.muted)}
                            Spacer();Image(systemName:saved==nil ? "arrow.down.circle":"book.pages")
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(task != nil);Divider()
                }
                Button{browser=true}label:{HStack{Image(systemName:"globe");Text("Đọc trên Wikisource tiếng Việt");Spacer();Image(systemName:"arrow.up.forward")}.font(.subheadline.weight(.medium)).padding(.vertical,8)}
            }.foregroundStyle(Palette.ink).padding(20).frame(maxWidth:720)
        }.frame(maxWidth:.infinity).background(Palette.paper)
        .task{if items.isEmpty{await load()}}
        .sheet(isPresented:$browser){WebReadingRoom(url:URL(string:"https://vi.wikisource.org/wiki/Trang_Ch%C3%ADnh")!).ignoresSafeArea()}
    }
    private func load() async{
        guard !loadingCatalog else{return};loadingCatalog=true;catalogError=nil
        defer{loadingCatalog=false}
        do{items=try await OnlineShelf.catalog()}catch{if !Task.isCancelled{catalogError="Chưa tải được tuyển tập. Bạn vẫn có thể mở sách trên máy."}}
    }
    private func fromAddress(){
        guard let url=URL(string:address.clean),url.scheme?.lowercased()=="https",url.host != nil else{
            downloadError="Hãy nhập đường dẫn bắt đầu bằng https:// tới tệp sách.";return
        };download(url)
    }
    private func download(_ url:URL){
        guard task==nil else{return};fieldFocused=false;percentage=nil;downloadError=nil
        task=Task{
            defer{task=nil;percentage=nil}
            do{
                let (file,name)=try await BookDownload(url){p in Task{@MainActor in percentage=p}}.run()
                if Task.isCancelled{try? FileManager.default.removeItem(at:file);return}
                shelf.downloaded(file,name:name)
            }catch{if !Task.isCancelled{downloadError=error.localizedDescription}}
        }
    }
}
