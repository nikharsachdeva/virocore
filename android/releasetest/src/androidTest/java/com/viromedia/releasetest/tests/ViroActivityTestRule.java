/*
 * Copyright (c) 2017-present, ViroMedia, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the  LICENSE file in the
 * root directory of this source tree. An additional grant  of patent rights can be found in
 * the PATENTS file in the same directory.
 */

package com.viromedia.releasetest.tests;

import android.app.Activity;
import android.support.test.rule.ActivityTestRule;
import android.util.Log;

import com.viro.core.ViroView;
import com.viromedia.releasetest.ViroReleaseTestActivity;

/**
 * Created by manish on 11/2/17.
 */

public class ViroActivityTestRule<T extends Activity> extends ActivityTestRule {
    private static final String TAG = ViroActivityTestRule.class.getSimpleName();

    public ViroActivityTestRule(final Class activityClass, final boolean initialTouchMode,
                                final boolean launchActivity) {
        super(activityClass, initialTouchMode, launchActivity);
    }

    @Override
    protected void beforeActivityLaunched() {
        // This is called before onCreate -> onStart -> onResume
        Log.i(TAG, "beforeActivityLaunched");
        super.beforeActivityLaunched();
    }

    @Override
    protected void afterActivityLaunched() {
        // This is called after onCreate -> onStart -> onResume, but before a @Before -> @Test -> @After
        Log.i(TAG, "afterActivityLaunched");
        super.afterActivityLaunched();

        // We start the renderer here, after activity construction; this way we don't block
        // the tests from starting by hogging the event queue for rendering.
        final ViroReleaseTestActivity activity = (ViroReleaseTestActivity) getActivity();
        activity.startRenderer();
    }

    @Override
    protected void afterActivityFinished() {
        Log.i(TAG, "afterActivityFinished");
        super.afterActivityFinished();
        final ViroReleaseTestActivity activity = (ViroReleaseTestActivity) getActivity();
        final ViroView viroView = activity.getViroView();

        // Fake the activity to be destroyed. The new ActivityTestRule does not exeercise
        // the complete Android Lifecycle from onCreate -> onDestroy
        try {
            runOnUiThread(() -> {
                viroView.onActivityStopped(activity);
                viroView.onActivityDestroyed(activity);
            });
        } catch (Throwable throwable) {
            throwable.printStackTrace();
        }
    }
}
