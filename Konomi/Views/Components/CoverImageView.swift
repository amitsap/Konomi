import SwiftUI

struct CoverImageView: View {
    let urlString: String?
    let cachedData: Data?
    let mediaType: MediaType
    var width: CGFloat = 80
    var height: CGFloat = 120

    @State private var loadedImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let data = cachedData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: KonomiTheme.coverRadius))
        .task {
            await loadIfNeeded()
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KonomiTheme.coverRadius)
                .fill(KonomiTheme.secondary.opacity(0.15))
            Image(systemName: mediaType.icon)
                .font(.system(size: 24))
                .foregroundStyle(KonomiTheme.secondary.opacity(0.5))
        }
    }

    private func loadIfNeeded() async {
        guard cachedData == nil, loadedImage == nil, let urlStr = urlString, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if let data = try? await CoverImageService.fetchImageData(from: urlStr),
           let img = UIImage(data: data) {
            loadedImage = img
        }
    }
}
