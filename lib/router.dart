import 'package:go_router/go_router.dart';

import 'pages/frame_page.dart';
import 'pages/home_page.dart';
import 'pages/spots_page.dart';
import 'pages/story_edit_page.dart';
import 'pages/tracking_page.dart';
import 'pages/trip_detail_page.dart';
import 'pages/trips_page.dart';

/// 三個底部 tab（記錄 / 旅程 / 相框）各是一個 branch，
/// 旅程詳情、遊記編輯、景點推薦掛在旅程 branch 下。
final router = GoRouter(
  initialLocation: '/tracking',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => HomePage(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tracking',
              builder: (context, state) => const TrackingPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/trips',
              builder: (context, state) => const TripsPage(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (context, state) => TripDetailPage(
                    tripId: int.parse(state.pathParameters['id']!),
                  ),
                  routes: [
                    GoRoute(
                      path: 'story',
                      builder: (context, state) => StoryEditPage(
                        tripId: int.parse(state.pathParameters['id']!),
                      ),
                    ),
                    GoRoute(
                      path: 'spots',
                      builder: (context, state) => SpotsPage(
                        tripId: int.parse(state.pathParameters['id']!),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/frame',
              builder: (context, state) => const FramePage(),
            ),
          ],
        ),
      ],
    ),
  ],
);
