import { BrowserRouter, Routes, Route } from "react-router-dom";
import { Toaster } from "react-hot-toast";

import Login from "./page/login/Login";
import DashboardLayout from "./layouts/DashboardLayout";
import DashboardHome from "./page/dashboard/DashboardHome";
import UserManagement from "./components/UserManagement";
import BookingManagement from "./page/booking/BookingManagement";
import Profile from "./page/profile/Profile";
import ReportsManagement from "./page/reports/ReportsManagement";
import ServiceCategories from "./page/categories/ServiceCategories";
import WorkerVerification from "./page/verification/WorkerVerification";
import ProtectedRoute from "./components/ProtectedRoute";
import SosAlerts from "./page/sos/SosAlerts";
import AdminManagement from './page/administrators/AdminManagement';
import { AdminAccessProvider } from './lib/AdminAccessContext';


export default function App() {
  return (
    <BrowserRouter>
      <AdminAccessProvider>
      <Toaster position="top-right" />

      <Routes>
        {/* Login */}
        <Route path="/" element={<Login />} />
        <Route path="/login" element={<Login />} />

        {/* Dashboard */}
        <Route path="/dashboard" element={<ProtectedRoute><DashboardLayout /></ProtectedRoute>}>
          <Route index element={<ProtectedRoute module="/dashboard"><DashboardHome /></ProtectedRoute>} />

        {/* Booking Management */}
        <Route path="bookings" element={<ProtectedRoute module="/dashboard/bookings"><BookingManagement /></ProtectedRoute>} />

        {/* User Management */}
        <Route path="users" element={<ProtectedRoute module="/dashboard/users"><UserManagement /></ProtectedRoute>} />

        {/* Admin Profile Management */}
        <Route path="profile" element={<Profile />} />
        
        {/* Report Management */}
        <Route path="reports" element={<ProtectedRoute module="/dashboard/reports"><ReportsManagement /></ProtectedRoute>} />

        {/* Service Categories */}
        <Route path="categories" element={<ProtectedRoute module="/dashboard/categories"><ServiceCategories /></ProtectedRoute>} />

        <Route path="verification" element={<ProtectedRoute module="/dashboard/verification"><WorkerVerification /></ProtectedRoute>} />

        {/* SOS emergency alerts */}
        <Route path="sos" element={<ProtectedRoute module="/dashboard/sos"><SosAlerts /></ProtectedRoute>} />
        <Route path="administrators" element={<ProtectedRoute module="/dashboard/administrators"><AdminManagement /></ProtectedRoute>} />


        </Route>

      </Routes>
      </AdminAccessProvider>
    </BrowserRouter>
  );
}
