import Forecast
import SwiftUI

struct WeatherView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    // A loose image from Resources/, found through Bundle.module
                    Image("banner", bundle: .module)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .listRowInsets(EdgeInsets())
                }
                // Data from the Forecast package dependency
                ForEach(Forecast.week) { day in
                    HStack {
                        Text(day.name).frame(width: 48, alignment: .leading)
                        Image(systemName: day.symbol).symbolRenderingMode(.multicolor)
                        Spacer()
                        Text("\(day.low)°").foregroundStyle(.secondary)
                        Text("\(day.high)°").bold()
                    }
                }
            }
            .navigationTitle("Weather")
        }
    }
}

#Preview {
    WeatherView()
}
