import SwiftUI

/// 「ヘルプ」メニューから開く使いかた。既定の「空フォルダ削除ヘルプ」は、
/// 存在しないヘルプブックを開こうとしてエラーダイアログになるので、そこに差し替える。
/// 外部サイトへ飛ばさないのは、サンドボックス内の小さなユーティリティで
/// ネットワークもブラウザも要らないほうが親切だから。
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section(
                    "このアプリがすること",
                    """
                    選んだフォルダの中を調べて、中身が何も入っていないフォルダを探します。\
                    入れ子になっていても、いちばん奥まで一度で見つけます。

                    選んだフォルダ自体は消えません。写真や書類など、実際のファイルが\
                    1つでも入っているフォルダも消えません。
                    """
                )

                section(
                    "使いかた",
                    """
                    1. フォルダをウィンドウにドラッグ＆ドロップするか、「フォルダを選択」で選びます。\
                    Dockのアイコンに直接ドロップすることもできます。
                    2. 見つかったものが一覧に出ます。消したくないものはチェックを外してください。
                    3. 行をダブルクリックすると、そのフォルダがFinderで開きます。行の右端の\
                    ボタンでも同じです。消す前に中身を確かめたいときに。
                    4. 「ゴミ箱に入れる」を押すと実行します。
                    """
                )

                section(
                    "ゴミ箱と完全削除",
                    """
                    既定ではゴミ箱に入れます。間違えたときはゴミ箱から元に戻せます。

                    「削除したものをゴミ箱に入れる」のチェックを外すと完全削除になり、\
                    元に戻せません。このときはボタンが赤くなり、確認画面でもEnterキーでは\
                    実行できないようにしてあります。
                    """
                )

                section(
                    "Finderの設定ファイル（.DS_Store）",
                    """
                    フォルダの並び順やウィンドウの大きさを覚えておくために、Finderが\
                    自動で作る見えないファイルです。これが1つ残っているだけで、\
                    見た目は空なのに「空ではない」と判定されてしまいます。

                    そのため既定では、これだけが残っているフォルダも空として扱います。

                    消してもフォルダ名や中のファイルには影響しません。次にそのフォルダを\
                    Finderで開くと自動的に作り直されるので、消えていないように見えることが\
                    ありますが、失敗したわけではありません。
                    """
                )

                section(
                    "時間がかかるとき",
                    """
                    ホームフォルダのような大きな場所を選ぶと、調べるのに時間がかかります。\
                    進み具合は「スキャン中... ○○項目」と表示されます。\
                    途中でやめたいときは「中止」を押してください。

                    中止したときは、調べかけの結果は捨てます。まだ見ていない場所に\
                    ファイルが残っているかもしれず、「空に見えただけ」のフォルダを\
                    消す候補にするわけにはいかないからです。
                    """
                )
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)
            Text(body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
