import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:waterfall_flow/waterfall_flow.dart';
import 'package:pure_live/modules/areas/widgets/area_card.dart';
import 'package:pure_live/modules/areas/favorite_areas_controller.dart';

class FavoriteAreasPage extends GetView<FavoriteAreasController> {
  const FavoriteAreasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraint) {
        final width = constraint.maxWidth;
        final crossAxisCount = width > 1280 ? 9 : (width > 960 ? 7 : (width > 640 ? 5 : 3));
        return Scaffold(
          appBar: AppBar(title: Text(S.of(context).favorite_areas)),
          body: Column(
            children: [
              TabBar(
                controller: controller.tabSiteController,
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: Sites().availableSites(containsAll: true).map<Widget>((e) => Tab(text: e.name)).toList(),
              ),
              Expanded(
                child: Obx(() {
                  return TabBarView(
                    controller: controller.tabSiteController,
                    children: Sites()
                        .availableSites(containsAll: true)
                        .map((e) => e.id)
                        .toList()
                        .map((e) => buildTabView(context, crossAxisCount, e))
                        .toList(),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildTabView(BuildContext context, int crossAxisCount, String siteId) {
    return Obx(
      () => controller.favoriteAreas.isNotEmpty
          ? WaterfallFlow.builder(
              padding: const EdgeInsets.all(0),
              controller: ScrollController(),
              gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemCount: siteId == Sites.allSite
                  ? controller.favoriteAreas.length
                  : controller.favoriteAreas.where((e) => e.platform == siteId).toList().length,
              itemBuilder: (context, index) => AreaCard(
                category: siteId == Sites.allSite
                    ? controller.favoriteAreas[index]
                    : controller.favoriteAreas.where((e) => e.platform == siteId).toList()[index],
              ),
            )
          : EmptyView(icon: Icons.area_chart_outlined, title: S.of(context).empty_areas_title, subtitle: ''),
    );
  }
}
