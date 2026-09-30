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


export default function App() {
  return (
    <BrowserRouter>
      <Toaster position="top-right" />

      <Routes>
        {/* Login */}
        <Route path="/" element={<Login />} />
        <Route path="/login" element={<Login />} />

        {/* Dashboard */}
        <Route path="/dashboard" element={<ProtectedRoute><DashboardLayout /></ProtectedRoute>}>
          <Route index element={<DashboardHome />} />

        {/* Booking Management */}
        <Route path="bookings" element={<BookingManagement />} />

        {/* User Management */}
        <Route path="users" element={<UserManagement />} />

        {/* Admin Profile Management */}
        <Route path="profile" element={<Profile />} />
        
        {/* Report Management */}
        <Route path="reports" element={<ReportsManagement />} />

        {/* Service Categories */}
        <Route path="categories" element={<ServiceCategories />} />

        <Route path="verification" element={<WorkerVerification />} />


        </Route>

      </Routes>
    </BrowserRouter>
  );
}
